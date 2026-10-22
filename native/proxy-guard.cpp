#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fwpmu.h>
#include <rpc.h>
#include <array>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <string>
#include <vector>
#pragma comment(lib, "fwpuclnt.lib")
#pragma comment(lib, "rpcrt4.lib")

namespace {
constexpr wchar_t kSublayerName[] = L"Claude Proxy Guard application policy";
constexpr wchar_t kFilterName[] = L"Claude Proxy Guard: loopback TCP proxy only";
constexpr UINT16 kSublayerWeight = 65535;
constexpr UINT8 kFilterWeight = 15;
constexpr UINT8 kTcp = 6;
constexpr UINT32 kFilterFlags = FWPM_FILTER_FLAG_PERSISTENT | FWPM_FILTER_FLAG_CLEAR_ACTION_RIGHT;
constexpr size_t kFilterCount = 4;

enum class Action { Install, Check, Remove };
struct Policy {
    Action action{};
    std::wstring executable;
    UINT16 port{};
    GUID sublayer{};
    std::array<GUID, kFilterCount> keys{};
};

// WFP allocations and transactions are always released, including error exits.
template <typename T> class WfpAllocation {
public:
    T* value = nullptr;
    ~WfpAllocation() { if (value) FwpmFreeMemory0(reinterpret_cast<void**>(&value)); }
    WfpAllocation() = default;
    WfpAllocation(const WfpAllocation&) = delete;
    WfpAllocation& operator=(const WfpAllocation&) = delete;
};
class Engine {
public:
    HANDLE value = nullptr;
    ~Engine() { if (value) FwpmEngineClose0(value); }
    Engine() = default;
    Engine(const Engine&) = delete;
    Engine& operator=(const Engine&) = delete;
};
class Transaction {
public:
    explicit Transaction(HANDLE engine) : engine_(engine) {}
    ~Transaction() { if (active_) FwpmTransactionAbort0(engine_); }
    DWORD Begin(bool readOnly) {
        const DWORD result = FwpmTransactionBegin0(engine_, readOnly ? FWPM_TXN_READ_ONLY : 0);
        active_ = result == ERROR_SUCCESS;
        return result;
    }
    DWORD Commit() {
        const DWORD result = FwpmTransactionCommit0(engine_);
        if (result == ERROR_SUCCESS) active_ = false;
        return result;
    }
    Transaction(const Transaction&) = delete;
    Transaction& operator=(const Transaction&) = delete;
private:
    HANDLE engine_;
    bool active_ = false;
};
bool SameText(const wchar_t* actual, const wchar_t* expected) {
    return actual && wcscmp(actual, expected) == 0;
}

bool ParseExecutable(const wchar_t* text, std::wstring& executable) {
    const size_t length = wcslen(text);
    const bool driveLetter = (text[0] >= L'A' && text[0] <= L'Z') ||
                            (text[0] >= L'a' && text[0] <= L'z');
    if (length < 7 || !driveLetter || text[1] != L':' || text[2] != L'\\' ||
        _wcsicmp(text + length - 4, L".exe") != 0) return false;
    for (size_t i = 0; i < length; ++i) {
        if (text[i] < L' ' || text[i] == L'"' || text[i] == L'/' ||
            (text[i] == L':' && i != 1)) return false;
    }
    // Reject UNC/device paths, mapped network drives, ADS and ambiguous paths.
    const wchar_t drive[] = { text[0], L':', L'\\', L'\0' };
    if (GetDriveTypeW(drive) == DRIVE_REMOTE) return false;
    const DWORD required = GetFullPathNameW(text, 0, nullptr, nullptr);
    if (!required) return false;
    std::vector<wchar_t> normalized(required);
    const DWORD written = GetFullPathNameW(text, required, normalized.data(), nullptr);
    if (!written || written >= required || _wcsicmp(text, normalized.data()) != 0) return false;
    executable = normalized.data();
    return true;
}
bool ParseArguments(int argc, wchar_t** argv, Policy& policy) {
    if (argc != 5) return false;
    if (wcscmp(argv[1], L"install") == 0) policy.action = Action::Install;
    else if (wcscmp(argv[1], L"check") == 0) policy.action = Action::Check;
    else if (wcscmp(argv[1], L"remove") == 0) policy.action = Action::Remove;
    else return false;
    if (!ParseExecutable(argv[2], policy.executable)) return false;
    unsigned long port = 0;
    if (!argv[3][0]) return false;
    for (const wchar_t* digit = argv[3]; *digit; ++digit) {
        if (*digit < L'0' || *digit > L'9') return false;
        port = port * 10 + static_cast<unsigned long>(*digit - L'0');
        if (port > 65535) return false;
    }
    if (port == 0) return false;
    policy.port = static_cast<UINT16>(port);
    if (wcslen(argv[4]) != 36 ||
        UuidFromStringW(reinterpret_cast<RPC_WSTR>(argv[4]), &policy.sublayer) != RPC_S_OK ||
        policy.sublayer == GUID{}) return false;
    // Each profile owns a random namespace. Keep v0.1 filter-key compatibility.
    for (size_t i = 0; i < kFilterCount; ++i) {
        policy.keys[i] = policy.sublayer;
        policy.keys[i].Data4[7] ^= static_cast<unsigned char>(i + 1);
    }
    return true;
}

bool MatchesSublayer(const FWPM_SUBLAYER0& sublayer, const Policy& policy) {
    const bool valid = sublayer.subLayerKey == policy.sublayer && SameText(sublayer.displayData.name, kSublayerName) &&
        sublayer.flags == FWPM_SUBLAYER_FLAG_PERSISTENT && sublayer.weight == kSublayerWeight &&
        sublayer.providerKey == nullptr && sublayer.providerData.size == 0;
    if (!valid) {
        printf("Sublayer mismatch: key=%d name=%d flags=0x%08lX expectedFlags=0x%08lX weight=%u expectedWeight=%u provider=%d providerDataSize=%lu\n",
            sublayer.subLayerKey == policy.sublayer, SameText(sublayer.displayData.name, kSublayerName),
            static_cast<unsigned long>(sublayer.flags), static_cast<unsigned long>(FWPM_SUBLAYER_FLAG_PERSISTENT),
            static_cast<unsigned>(sublayer.weight), static_cast<unsigned>(kSublayerWeight),
            sublayer.providerKey != nullptr, static_cast<unsigned long>(sublayer.providerData.size));
    }
    return valid;
}

// Diagnostics contain policy metadata only: never executable identity bytes or paths.
void PrintFilterDiagnostics(const FWPM_FILTER0& filter, const Policy& policy, size_t index) {
    const GUID layer = index == 3 ? FWPM_LAYER_ALE_AUTH_CONNECT_V6 : FWPM_LAYER_ALE_AUTH_CONNECT_V4;
    printf("Filter[%zu] metadata: key=%d sublayer=%d layer=%d name=%d flags=0x%08lX expectedFlags=0x%08lX action=0x%08lX expectedAction=0x%08lX weightType=%u expectedWeightType=%u provider=%d providerDataSize=%lu conditionCount=%lu\n",
        index, filter.filterKey == policy.keys[index], filter.subLayerKey == policy.sublayer,
        filter.layerKey == layer, SameText(filter.displayData.name, kFilterName),
        static_cast<unsigned long>(filter.flags), static_cast<unsigned long>(kFilterFlags),
        static_cast<unsigned long>(filter.action.type), static_cast<unsigned long>(FWP_ACTION_BLOCK),
        static_cast<unsigned>(filter.weight.type), static_cast<unsigned>(FWP_UINT8),
        filter.providerKey != nullptr, static_cast<unsigned long>(filter.providerData.size),
        static_cast<unsigned long>(filter.numFilterConditions));
    if (filter.weight.type == FWP_UINT8) printf("  weight8=%u expectedWeight8=%u\n", static_cast<unsigned>(filter.weight.uint8), static_cast<unsigned>(kFilterWeight));
    if (filter.weight.type == FWP_UINT64 && filter.weight.uint64) printf("  weight64=%llu\n", static_cast<unsigned long long>(*filter.weight.uint64));
    if (!filter.filterCondition) { puts("  conditions=null"); return; }
    for (UINT32 i = 0; i < filter.numFilterConditions && i < 8; ++i) {
        const FWPM_FILTER_CONDITION0& c = filter.filterCondition[i];
        const char* field = c.fieldKey == FWPM_CONDITION_ALE_APP_ID ? "application" :
            c.fieldKey == FWPM_CONDITION_IP_REMOTE_ADDRESS ? "remote-address" :
            c.fieldKey == FWPM_CONDITION_IP_REMOTE_PORT ? "remote-port" :
            c.fieldKey == FWPM_CONDITION_IP_PROTOCOL ? "protocol" : "unknown";
        printf("  condition[%lu] field=%s match=%u valueType=%u", static_cast<unsigned long>(i), field,
            static_cast<unsigned>(c.matchType), static_cast<unsigned>(c.conditionValue.type));
        if (c.conditionValue.type == FWP_UINT8) printf(" uint8=%u", static_cast<unsigned>(c.conditionValue.uint8));
        if (c.conditionValue.type == FWP_UINT16) printf(" uint16=%u", static_cast<unsigned>(c.conditionValue.uint16));
        if (c.conditionValue.type == FWP_UINT32) printf(" uint32=0x%08lX", static_cast<unsigned long>(c.conditionValue.uint32));
        if (c.conditionValue.type == FWP_BYTE_BLOB_TYPE) printf(" blobPresent=%d blobSize=%lu",
            c.conditionValue.byteBlob != nullptr,
            c.conditionValue.byteBlob ? static_cast<unsigned long>(c.conditionValue.byteBlob->size) : 0ul);
        puts("");
    }
}
bool MatchesFilter(const FWPM_FILTER0& filter, const Policy& policy, size_t index,
                   const FWP_BYTE_BLOB* appId) {
    const GUID layer = index == 3 ? FWPM_LAYER_ALE_AUTH_CONNECT_V6 : FWPM_LAYER_ALE_AUTH_CONNECT_V4;
    if (filter.filterKey != policy.keys[index] || filter.subLayerKey != policy.sublayer ||
        filter.layerKey != layer || !SameText(filter.displayData.name, kFilterName) ||
        // BFE may add INDEXED to an installed filter. No other extra flags (in
        // particular DISABLED) are acceptable for an enforced client policy.
        (filter.flags & ~FWPM_FILTER_FLAG_INDEXED) != kFilterFlags || filter.action.type != FWP_ACTION_BLOCK ||
        filter.weight.type != FWP_UINT8 || filter.weight.uint8 != kFilterWeight ||
        filter.providerKey != nullptr || filter.providerData.size != 0 ||
        filter.numFilterConditions != (index == 3 ? 1u : 2u) || !filter.filterCondition) return false;
    const FWPM_FILTER_CONDITION0& identity = filter.filterCondition[0];
    if (identity.fieldKey != FWPM_CONDITION_ALE_APP_ID || identity.matchType != FWP_MATCH_EQUAL ||
        identity.conditionValue.type != FWP_BYTE_BLOB_TYPE || !identity.conditionValue.byteBlob ||
        !identity.conditionValue.byteBlob->size || !identity.conditionValue.byteBlob->data) return false;
    if (appId && (identity.conditionValue.byteBlob->size != appId->size ||
        memcmp(identity.conditionValue.byteBlob->data, appId->data, appId->size) != 0)) return false;
    if (index == 3) return true;
    const FWPM_FILTER_CONDITION0& condition = filter.filterCondition[1];
    if (condition.matchType != FWP_MATCH_NOT_EQUAL) return false;
    switch (index) {
    case 0:
        return condition.fieldKey == FWPM_CONDITION_IP_REMOTE_ADDRESS &&
            condition.conditionValue.type == FWP_UINT32 && condition.conditionValue.uint32 == 0x7f000001;
    case 1:
        return condition.fieldKey == FWPM_CONDITION_IP_REMOTE_PORT &&
            condition.conditionValue.type == FWP_UINT16 && condition.conditionValue.uint16 == policy.port;
    case 2:
        return condition.fieldKey == FWPM_CONDITION_IP_PROTOCOL &&
            condition.conditionValue.type == FWP_UINT8 && condition.conditionValue.uint8 == kTcp;
    default:
        return false;
    }
}
struct ExistingPolicy {
    bool sublayer = false;
    std::array<bool, kFilterCount> filters{};
};
DWORD InspectPolicy(HANDLE engine, const Policy& policy, const FWP_BYTE_BLOB* appId, ExistingPolicy& existing) {
    WfpAllocation<FWPM_SUBLAYER0> sublayer;
    DWORD result = FwpmSubLayerGetByKey0(engine, &policy.sublayer, &sublayer.value);
    if (result != ERROR_SUCCESS && result != FWP_E_SUBLAYER_NOT_FOUND) return result;
    if (result == ERROR_SUCCESS) {
        if (!MatchesSublayer(*sublayer.value, policy)) return ERROR_INVALID_DATA;
        existing.sublayer = true;
    }
    for (size_t i = 0; i < kFilterCount; ++i) {
        WfpAllocation<FWPM_FILTER0> filter;
        result = FwpmFilterGetByKey0(engine, &policy.keys[i], &filter.value);
        if (result != ERROR_SUCCESS && result != FWP_E_FILTER_NOT_FOUND) return result;
        if (result == ERROR_SUCCESS) {
            if (!existing.sublayer || !MatchesFilter(*filter.value, policy, i, appId)) {
                PrintFilterDiagnostics(*filter.value, policy, i);
                if (appId) printf("  expectedAppBlobSize=%lu\n", static_cast<unsigned long>(appId->size));
                return ERROR_INVALID_DATA;
            }
            existing.filters[i] = true;
        }
    }
    return ERROR_SUCCESS;
}
DWORD AddFilter(HANDLE engine, const Policy& policy, size_t index, FWP_BYTE_BLOB* appId) {
    std::array<FWPM_FILTER_CONDITION0, 2> conditions{};
    conditions[0].fieldKey = FWPM_CONDITION_ALE_APP_ID;
    conditions[0].matchType = FWP_MATCH_EQUAL;
    conditions[0].conditionValue.type = FWP_BYTE_BLOB_TYPE;
    conditions[0].conditionValue.byteBlob = appId;
    conditions[1].matchType = FWP_MATCH_NOT_EQUAL;
    switch (index) {
    case 0:
        conditions[1].fieldKey = FWPM_CONDITION_IP_REMOTE_ADDRESS;
        conditions[1].conditionValue.type = FWP_UINT32;
        conditions[1].conditionValue.uint32 = 0x7f000001;
        break;
    case 1:
        conditions[1].fieldKey = FWPM_CONDITION_IP_REMOTE_PORT;
        conditions[1].conditionValue.type = FWP_UINT16;
        conditions[1].conditionValue.uint16 = policy.port;
        break;
    case 2:
        conditions[1].fieldKey = FWPM_CONDITION_IP_PROTOCOL;
        conditions[1].conditionValue.type = FWP_UINT8;
        conditions[1].conditionValue.uint8 = kTcp;
        break;
    default:
        break; // IPv6 is blocked for every destination, port and protocol.
    }
    FWPM_FILTER0 filter{};
    filter.filterKey = policy.keys[index];
    filter.subLayerKey = policy.sublayer;
    filter.layerKey = index == 3 ? FWPM_LAYER_ALE_AUTH_CONNECT_V6 : FWPM_LAYER_ALE_AUTH_CONNECT_V4;
    filter.displayData.name = const_cast<wchar_t*>(kFilterName);
    filter.flags = kFilterFlags;
    filter.weight.type = FWP_UINT8;
    filter.weight.uint8 = kFilterWeight;
    filter.action.type = FWP_ACTION_BLOCK;
    filter.numFilterConditions = index == 3 ? 1 : 2;
    filter.filterCondition = conditions.data();
    return FwpmFilterAdd0(engine, &filter, nullptr, nullptr);
}
DWORD ApplyPolicy(HANDLE engine, const Policy& policy, FWP_BYTE_BLOB* appId) {
    Transaction transaction(engine);
    DWORD result = transaction.Begin(policy.action == Action::Check);
    if (result != ERROR_SUCCESS) return result;
    ExistingPolicy existing;
    result = InspectPolicy(engine, policy, appId, existing);
    if (result != ERROR_SUCCESS) return result;
    if (policy.action == Action::Check) {
        if (!existing.sublayer) return static_cast<DWORD>(FWP_E_SUBLAYER_NOT_FOUND);
        for (bool present : existing.filters) if (!present) return static_cast<DWORD>(FWP_E_FILTER_NOT_FOUND);
    } else if (policy.action == Action::Install) {
        if (!existing.sublayer) {
            FWPM_SUBLAYER0 sublayer{};
            sublayer.subLayerKey = policy.sublayer;
            sublayer.displayData.name = const_cast<wchar_t*>(kSublayerName);
            sublayer.flags = FWPM_SUBLAYER_FLAG_PERSISTENT;
            sublayer.weight = kSublayerWeight;
            result = FwpmSubLayerAdd0(engine, &sublayer, nullptr);
            if (result != ERROR_SUCCESS) return result;
        }
        for (size_t i = 0; i < kFilterCount; ++i) {
            // Never replace a filter: inspection must prove an existing filter matches.
            if (!existing.filters[i]) result = AddFilter(engine, policy, i, appId);
            if (result != ERROR_SUCCESS) return result;
        }
    } else {
        for (size_t i = 0; i < kFilterCount; ++i) {
            if (existing.filters[i]) result = FwpmFilterDeleteByKey0(engine, &policy.keys[i]);
            if (result != ERROR_SUCCESS) return result;
        }
        if (existing.sublayer) result = FwpmSubLayerDeleteByKey0(engine, &policy.sublayer);
        if (result != ERROR_SUCCESS) return result;
    }
    return transaction.Commit();
}
} // namespace

int wmain(int argc, wchar_t** argv) {
    Policy policy;
    if (!ParseArguments(argc, argv, policy)) {
        puts("Usage: proxy-guard install|check|remove absolute-exe port nonempty-policy-guid");
        return 2;
    }
    WfpAllocation<FWP_BYTE_BLOB> appId;
    if (policy.action != Action::Remove) {
        const DWORD attributes = GetFileAttributesW(policy.executable.c_str());
        if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY)) {
            puts("Executable does not exist or is not a file.");
            return 1;
        }
        const DWORD result = FwpmGetAppIdFromFileName0(policy.executable.c_str(), &appId.value);
        if (result != ERROR_SUCCESS || !appId.value || !appId.value->data || !appId.value->size) {
            printf("Cannot resolve application identity: %lu\n", result);
            return 1;
        }
    }
    // Removal verifies names, namespace and shape but permits an already deleted exe.
    Engine engine;
    DWORD result = FwpmEngineOpen0(nullptr, RPC_C_AUTHN_WINNT, nullptr, nullptr, &engine.value);
    if (result == ERROR_SUCCESS) result = ApplyPolicy(engine.value, policy, appId.value);
    if (result != ERROR_SUCCESS) {
        printf("Policy operation failed: %lu (0x%08lX). Administrator rights are required.\n", result, result);
        if (result == ERROR_INVALID_DATA) puts("Existing namespace or filter does not match this policy; nothing changed.");
        return 1;
    }
    puts(policy.action == Action::Check ? "Verified 4/4 persistent application filters and sublayer." :
        policy.action == Action::Install ? "Policy installed; matching existing rules retained." : "Policy removed.");
    return 0;
}
