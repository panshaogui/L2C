#include "http_fetcher.h"
#include <curl/curl.h>
#include <string.h>

struct MemoryStruct {
  char *memory;
  size_t size;
  size_t max_size;
};

// libcurl 的底层数据灌入回调
static size_t WriteMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp) {
  size_t realsize = size * nmemb;
  struct MemoryStruct *mem = (struct MemoryStruct *)userp;
  
  if(mem->size + realsize + 1 > mem->max_size) return 0; // 防止栈溢出！
  
  memcpy(&(mem->memory[mem->size]), contents, realsize);
  mem->size += realsize;
  mem->memory[mem->size] = 0; // C 字符串安全终结符
  return realsize;
}

// 绝对阻塞的极速网络请求
int http_get(const char* url, char* out_buf, int max_len) {
  CURL *curl_handle;
  CURLcode res;
  struct MemoryStruct chunk;
  
  chunk.memory = out_buf;
  chunk.size = 0;
  chunk.max_size = max_len;
  out_buf[0] = '\0';

  curl_global_init(CURL_GLOBAL_ALL);
  curl_handle = curl_easy_init();
  curl_easy_setopt(curl_handle, CURLOPT_URL, url);
  curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
  curl_easy_setopt(curl_handle, CURLOPT_WRITEDATA, (void *)&chunk);
  curl_easy_setopt(curl_handle, CURLOPT_USERAGENT, "L2C-HFT-Sniper/1.0");

  res = curl_easy_perform(curl_handle);
  curl_easy_cleanup(curl_handle);
  curl_global_cleanup();
  
  if(res != CURLE_OK) return -1;
  return (int)chunk.size;
}