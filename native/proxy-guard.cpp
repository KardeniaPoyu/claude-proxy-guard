#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fwpmu.h>
#include <rpc.h>
#include <cstdio>
#include <cwchar>
#include <cstring>
#pragma comment(lib,"fwpuclnt.lib")
#pragma comment(lib,"rpcrt4.lib")

// Each policy has a fresh namespace. Never reuse another profile's GUID.
int wmain(int argc,wchar_t** argv){
 if(argc!=5){puts("Usage: proxy-guard install|check|remove absolute-exe port policy-guid");return 2;}
 bool remove=wcscmp(argv[1],L"remove")==0;
 bool check=wcscmp(argv[1],L"check")==0;
 if(!remove&&!check&&wcscmp(argv[1],L"install")!=0)return 2;
 const wchar_t* app=argv[2];
 if(wcslen(app)<4 || app[1]!=L':' || app[2]!=L'\\')return 2;
 wchar_t* end=nullptr; long number=wcstol(argv[3],&end,10);
 if(!end||*end||number<1||number>65535)return 2;
 const UINT16 port=static_cast<UINT16>(number);
 GUID sub={};if(UuidFromStringW((RPC_WSTR)argv[4],&sub)!=RPC_S_OK)return 2;
 GUID keys[4]={sub,sub,sub,sub};
 for(int i=0;i<4;i++)keys[i].Data4[7]^=static_cast<unsigned char>(i+1);
 HANDLE engine=nullptr; FWP_BYTE_BLOB* id=nullptr; DWORD e=FwpmEngineOpen0(nullptr,RPC_C_AUTHN_WINNT,nullptr,nullptr,&engine);
 if(e){printf("engine error %lu\n",e);return 1;}
 if(check){
  e=FwpmGetAppIdFromFileName0(app,&id);
  if(e||!id||!id->data||!id->size){printf("App identity error %lu\n",e);FwpmEngineClose0(engine);return 1;}
  int count=0;
  for(int i=0;i<4;i++){
   FWPM_FILTER0* f=nullptr;DWORD read=FwpmFilterGetByKey0(engine,&keys[i],&f);
   if(read){printf("Filter query error %lu (check requires administrator rights)\n",read);FwpmFreeMemory0((void**)&id);FwpmEngineClose0(engine);return 1;}
   GUID layer=i==3?FWPM_LAYER_ALE_AUTH_CONNECT_V6:FWPM_LAYER_ALE_AUTH_CONNECT_V4;
   bool valid=f->action.type==FWP_ACTION_BLOCK && f->subLayerKey==sub && f->layerKey==layer && (f->flags&FWPM_FILTER_FLAG_PERSISTENT) && (f->flags&FWPM_FILTER_FLAG_CLEAR_ACTION_RIGHT) && f->numFilterConditions==(i==3?1u:2u);
   if(valid){const auto& c=f->filterCondition[0];valid=c.fieldKey==FWPM_CONDITION_ALE_APP_ID&&c.matchType==FWP_MATCH_EQUAL&&c.conditionValue.type==FWP_BYTE_BLOB_TYPE&&c.conditionValue.byteBlob&&c.conditionValue.byteBlob->size==id->size&&!memcmp(c.conditionValue.byteBlob->data,id->data,id->size);}
   if(valid&&i<3){const auto& c=f->filterCondition[1];valid=c.matchType==FWP_MATCH_NOT_EQUAL;
    if(i==0)valid=valid&&c.fieldKey==FWPM_CONDITION_IP_REMOTE_ADDRESS&&c.conditionValue.type==FWP_UINT32&&c.conditionValue.uint32==0x7f000001;
    if(i==1)valid=valid&&c.fieldKey==FWPM_CONDITION_IP_REMOTE_PORT&&c.conditionValue.type==FWP_UINT16&&c.conditionValue.uint16==port;
    if(i==2)valid=valid&&c.fieldKey==FWPM_CONDITION_IP_PROTOCOL&&c.conditionValue.type==FWP_UINT8&&c.conditionValue.uint8==6;
   }
   if(valid){count++;} FwpmFreeMemory0((void**)&f);
  }
  FwpmFreeMemory0((void**)&id);
  printf("Persistent CC-only filters verified (identity, address, port, protocol, IPv6): %d/4\n",count);FwpmEngineClose0(engine);return count==4?0:1;
 }
 e=FwpmTransactionBegin0(engine,0);if(e){printf("transaction error %lu\n",e);FwpmEngineClose0(engine);return 1;}
 if(remove){
  for(int i=0;i<4;i++){e=FwpmFilterDeleteByKey0(engine,&keys[i]);if(e!=0&&e!=FWP_E_FILTER_NOT_FOUND)break;e=0;}
  if(!e){e=FwpmSubLayerDeleteByKey0(engine,&sub);if(e==FWP_E_SUBLAYER_NOT_FOUND)e=0;}
 }else{
  e=FwpmGetAppIdFromFileName0(app,&id);
  if(!e && (!id || !id->data || !id->size))e=ERROR_INVALID_DATA;
  if(!e){
   FWPM_SUBLAYER0 s={};s.subLayerKey=sub;s.displayData.name=(wchar_t*)L"Claude Proxy Guard application policy";s.flags=FWPM_SUBLAYER_FLAG_PERSISTENT;s.weight=65535;
   e=FwpmSubLayerAdd0(engine,&s,nullptr);if(e==FWP_E_ALREADY_EXISTS)e=0;
  }
  for(int i=0;i<4&&!e;i++){
   DWORD old=FwpmFilterDeleteByKey0(engine,&keys[i]);if(old!=0&&old!=FWP_E_FILTER_NOT_FOUND){e=old;break;}
   FWPM_FILTER_CONDITION0 c[2]={};
   c[0].fieldKey=FWPM_CONDITION_ALE_APP_ID;c[0].matchType=FWP_MATCH_EQUAL;c[0].conditionValue.type=FWP_BYTE_BLOB_TYPE;c[0].conditionValue.byteBlob=id;
   c[1].matchType=FWP_MATCH_NOT_EQUAL;
   if(i==0){c[1].fieldKey=FWPM_CONDITION_IP_REMOTE_ADDRESS;c[1].conditionValue.type=FWP_UINT32;c[1].conditionValue.uint32=0x7f000001;}
   if(i==1){c[1].fieldKey=FWPM_CONDITION_IP_REMOTE_PORT;c[1].conditionValue.type=FWP_UINT16;c[1].conditionValue.uint16=port;}
   if(i==2){c[1].fieldKey=FWPM_CONDITION_IP_PROTOCOL;c[1].conditionValue.type=FWP_UINT8;c[1].conditionValue.uint8=6;}
   FWPM_FILTER0 f={};f.filterKey=keys[i];f.subLayerKey=sub;f.layerKey=i==3?FWPM_LAYER_ALE_AUTH_CONNECT_V6:FWPM_LAYER_ALE_AUTH_CONNECT_V4;
   f.displayData.name=(wchar_t*)L"Claude Proxy Guard: loopback TCP proxy only";f.flags=FWPM_FILTER_FLAG_PERSISTENT|FWPM_FILTER_FLAG_CLEAR_ACTION_RIGHT;
   f.weight.type=FWP_UINT8;f.weight.uint8=15;f.action.type=FWP_ACTION_BLOCK;f.numFilterConditions=i==3?1:2;f.filterCondition=c;
   e=FwpmFilterAdd0(engine,&f,nullptr,nullptr);
  }
 }
 if(!e)e=FwpmTransactionCommit0(engine);else FwpmTransactionAbort0(engine);
 if(id){FwpmFreeMemory0((void**)&id);} FwpmEngineClose0(engine);
 printf("%s result: %lu\n",remove?"remove":"install",e);return e?1:0;
}
