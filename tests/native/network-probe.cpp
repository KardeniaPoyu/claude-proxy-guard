#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#pragma comment(lib, "ws2_32.lib")

// Test-only executable. It never resolves names or contacts non-loopback addresses.
int main(int argc, char** argv) {
    if (argc != 5) return 2;
    const bool server = !strcmp(argv[1], "serve");
    if (!server && strcmp(argv[1], "probe")) return 2;
    const bool udp = !strcmp(argv[2], "udp");
    if (!udp && strcmp(argv[2], "tcp")) return 2;
    const bool ipv6 = !strcmp(argv[3], "::1");
    if (!ipv6 && strcmp(argv[3], "127.0.0.1") && strcmp(argv[3], "127.0.0.2")) return 2;
    char* end = nullptr; const long port = strtol(argv[4], &end, 10);
    if (!end || *end || port < 1 || port > 65535) return 2;
    WSADATA data{}; if (WSAStartup(MAKEWORD(2, 2), &data)) return 2;
    SOCKET sock = socket(ipv6 ? AF_INET6 : AF_INET, udp ? SOCK_DGRAM : SOCK_STREAM, 0);
    if (sock == INVALID_SOCKET) return 2;
    sockaddr_storage address{};
    const int addressSize = ipv6 ? sizeof(sockaddr_in6) : sizeof(sockaddr_in);
    if (ipv6) {
        auto* a = reinterpret_cast<sockaddr_in6*>(&address);
        a->sin6_family = AF_INET6; a->sin6_port = htons(static_cast<u_short>(port));
        inet_pton(AF_INET6, argv[3], &a->sin6_addr);
    } else {
        auto* a = reinterpret_cast<sockaddr_in*>(&address);
        a->sin_family = AF_INET; a->sin_port = htons(static_cast<u_short>(port));
        inet_pton(AF_INET, argv[3], &a->sin_addr);
    }
    constexpr char marker[] = "guard-probe";
    const DWORD timeout = 2000;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
    if (server) {
        const BOOL exclusive = TRUE;
        setsockopt(sock, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, reinterpret_cast<const char*>(&exclusive), sizeof(exclusive));
        if (bind(sock, reinterpret_cast<sockaddr*>(&address), addressSize) == SOCKET_ERROR) return 2;
        if (!udp && listen(sock, SOMAXCONN) == SOCKET_ERROR) return 2;
        puts("READY"); fflush(stdout);
        for (;;) {
            if (udp) {
                char buffer[64]{}; sockaddr_storage peer{}; int size = sizeof(peer);
                const int count = recvfrom(sock, buffer, sizeof(buffer), 0, reinterpret_cast<sockaddr*>(&peer), &size);
                if (count > 0) sendto(sock, marker, sizeof(marker), 0, reinterpret_cast<sockaddr*>(&peer), size);
            } else {
                SOCKET peer = accept(sock, nullptr, nullptr);
                if (peer == INVALID_SOCKET) return 2;
                send(peer, marker, sizeof(marker), 0); closesocket(peer);
            }
        }
    }
    u_long nonblocking = 1; ioctlsocket(sock, FIONBIO, &nonblocking);
    int connected = connect(sock, reinterpret_cast<sockaddr*>(&address), addressSize);
    if (connected == SOCKET_ERROR && WSAGetLastError() == WSAEWOULDBLOCK) {
        fd_set writable; FD_ZERO(&writable); FD_SET(sock, &writable);
        timeval wait{2, 0};
        if (select(0, nullptr, &writable, nullptr, &wait) > 0) {
            int error = 0; int size = sizeof(error);
            if (getsockopt(sock, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&error), &size) == 0 && error == 0) connected = 0;
        }
    }
    nonblocking = 0; ioctlsocket(sock, FIONBIO, &nonblocking);
    bool success = connected == 0;
    if (success && udp) success = send(sock, marker, sizeof(marker), 0) != SOCKET_ERROR;
    char response[64]{};
    if (success) {
        const int received = recv(sock, response, sizeof(response), 0);
        success = received == sizeof(marker) && !memcmp(response, marker, sizeof(marker));
    }
    closesocket(sock); WSACleanup();
    puts(success ? "REACHABLE" : "UNREACHABLE");
    return success ? 0 : 5;
}
