#include "wifi.h"
#include "hardware/flash.h"
#include "lwip/ip4_addr.h"
#include "lwip/netif.h"
#include "pico/cyw43_arch.h"
#include "pico/flash.h"
#include <stdio.h>
#include <string.h>

#define CREDS_OFFSET (PICO_FLASH_SIZE_BYTES - FLASH_SECTOR_SIZE)
#define CREDS_MAGIC 0x57494649u

typedef struct {
  uint32_t magic;
  char ssid[33];
  char password[64];
} creds_t;

static_assert(sizeof(creds_t) <= FLASH_PAGE_SIZE, "creds fit one page");

static bool ready;
static char ip[16];
static const char *failure;

static const creds_t *saved_creds(void) {
  const creds_t *c = (const creds_t *)(XIP_BASE + CREDS_OFFSET);
  return c->magic == CREDS_MAGIC ? c : NULL;
}

static void flash_write_page(void *page) {
  flash_range_erase(CREDS_OFFSET, FLASH_SECTOR_SIZE);
  if (page)
    flash_range_program(CREDS_OFFSET, page, FLASH_PAGE_SIZE);
}

static bool connect(const char *ssid, const char *password) {
  printf("wifi: connecting to %s\n", ssid);
  uint32_t auth = password[0] ? CYW43_AUTH_WPA2_AES_PSK : CYW43_AUTH_OPEN;
  int err = cyw43_arch_wifi_connect_timeout_ms(ssid, password, auth, 30000);
  failure = err == PICO_OK              ? NULL
            : err == PICO_ERROR_BADAUTH ? "bad_auth"
            : err == PICO_ERROR_TIMEOUT ? "timeout"
                                        : "failed";
  if (failure) {
    printf("wifi: connect failed: %s\n", failure);
    return false;
  }
  snprintf(ip, sizeof ip, "%s", ip4addr_ntoa(netif_ip4_addr(netif_list)));
  printf("wifi: up, ip %s\n", ip);
  return true;
}

void wifi_init(void) {
  if (cyw43_arch_init()) {
    printf("wifi: init failed\n");
    return;
  }
  ready = true;
  cyw43_arch_enable_sta_mode();
}

static bool check_creds(trilog_t *t, const trilog_value_t *in) {
  if (!ready)
    return trilog_error(t, "system_error(wifi_init_failed)");
  if (!in[0].a[0] || strlen(in[0].a) >= sizeof((creds_t){0}.ssid))
    return trilog_error(t, "domain_error(ssid, _)");
  size_t n = strlen(in[1].a);
  if (n >= sizeof((creds_t){0}.password) || (n > 0 && n < 8))
    return trilog_error(t, "domain_error(wpa2_password, _)");
  return true;
}

static bool wifi_connect(trilog_t *t, void *ud, const trilog_value_t *in,
                         trilog_value_t *out) {
  (void)ud, (void)out;
  return check_creds(t, in) && connect(in[0].a, in[1].a);
}

// The password stays in C: it never becomes an atom.
static bool wifi_connect_saved(trilog_t *t, void *ud, const trilog_value_t *in,
                               trilog_value_t *out) {
  (void)ud, (void)in, (void)out;
  if (!ready)
    return trilog_error(t, "system_error(wifi_init_failed)");
  const creds_t *c = saved_creds();
  return c && connect(c->ssid, c->password);
}

static bool wifi_save(trilog_t *t, void *ud, const trilog_value_t *in,
                      trilog_value_t *out) {
  (void)ud, (void)out;
  if (!check_creds(t, in))
    return false;
  static uint8_t page[FLASH_PAGE_SIZE];
  memset(page, 0xff, sizeof page);
  creds_t c = {.magic = CREDS_MAGIC};
  strcpy(c.ssid, in[0].a);
  strcpy(c.password, in[1].a);
  memcpy(page, &c, sizeof c);
  if (flash_safe_execute(flash_write_page, page, 1000) != PICO_OK)
    return trilog_error(t, "system_error(flash_write)");
  return true;
}

static bool wifi_forget(trilog_t *t, void *ud, const trilog_value_t *in,
                        trilog_value_t *out) {
  (void)ud, (void)in, (void)out;
  if (flash_safe_execute(flash_write_page, NULL, 1000) != PICO_OK)
    return trilog_error(t, "system_error(flash_write)");
  return true;
}

static bool wifi_saved(trilog_t *t, void *ud, const trilog_value_t *in,
                       trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  const creds_t *c = saved_creds();
  out[0].a = c ? c->ssid : NULL;
  return c != NULL;
}

static bool wifi_status(trilog_t *t, void *ud, const trilog_value_t *in,
                        trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  int s = ready ? cyw43_tcpip_link_status(&cyw43_state, CYW43_ITF_STA)
                : CYW43_LINK_FAIL;
  out[0].a = s == CYW43_LINK_UP        ? "up"
             : s == CYW43_LINK_NOIP    ? "no_ip"
             : s == CYW43_LINK_JOIN    ? "joined"
             : s == CYW43_LINK_BADAUTH ? "bad_auth"
             : s == CYW43_LINK_NONET   ? "no_network"
             : s < 0                   ? "failed"
             : failure                 ? failure
                                       : "down";
  return true;
}

static bool wifi_ip(trilog_t *t, void *ud, const trilog_value_t *in,
                    trilog_value_t *out) {
  (void)t, (void)ud, (void)in;
  if (!ready ||
      cyw43_tcpip_link_status(&cyw43_state, CYW43_ITF_STA) != CYW43_LINK_UP)
    return false;
  snprintf(ip, sizeof ip, "%s", ip4addr_ntoa(netif_ip4_addr(netif_list)));
  out[0].a = ip;
  return true;
}

static int print_scan_result(void *env, const cyw43_ev_scan_result_t *r) {
  (void)env;
  printf("%02x:%02x:%02x:%02x:%02x:%02x  ch %2u  %4d dBm  auth 0x%02x  %.*s\n",
         r->bssid[0], r->bssid[1], r->bssid[2], r->bssid[3], r->bssid[4],
         r->bssid[5], r->channel, r->rssi, r->auth_mode, r->ssid_len, r->ssid);
  return 0;
}

static bool wifi_scan(trilog_t *t, void *ud, const trilog_value_t *in,
                      trilog_value_t *out) {
  (void)ud, (void)in, (void)out;
  if (!ready)
    return trilog_error(t, "system_error(wifi_init_failed)");
  cyw43_wifi_scan_options_t opts = {0};
  if (cyw43_wifi_scan(&cyw43_state, &opts, NULL, print_scan_result))
    return trilog_error(t, "system_error(wifi_scan_failed)");
  while (cyw43_wifi_scan_active(&cyw43_state))
    sleep_ms(50);
  return true;
}

static bool wifi_trace(trilog_t *t, void *ud, const trilog_value_t *in,
                       trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  if (in[0].i)
    cyw43_state.trace_flags |= CYW43_TRACE_ASYNC_EV;
  else
    cyw43_state.trace_flags &= ~CYW43_TRACE_ASYNC_EV;
  return true;
}

static bool onboard_led(trilog_t *t, void *ud, const trilog_value_t *in,
                        trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  if (ready)
    cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, in[0].i != 0);
  return ready;
}

void wifi_register(trilog_t *t) {
  trilog_register(t, "wifi_connect", "aa", wifi_connect, NULL);
  trilog_register(t, "wifi_connect_saved", "", wifi_connect_saved, NULL);
  trilog_register(t, "wifi_save", "aa", wifi_save, NULL);
  trilog_register(t, "wifi_forget", "", wifi_forget, NULL);
  trilog_register(t, "wifi_saved", ">a", wifi_saved, NULL);
  trilog_register(t, "wifi_status", ">a", wifi_status, NULL);
  trilog_register(t, "wifi_ip", ">a", wifi_ip, NULL);
  trilog_register(t, "wifi_trace", "i", wifi_trace, NULL);
  trilog_register(t, "wifi_scan", "", wifi_scan, NULL);
  trilog_register(t, "onboard_led", "i", onboard_led, NULL);
}
