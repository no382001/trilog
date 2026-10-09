#include "leds.h"
#include "hardware/gpio.h"
#include "pico/stdlib.h"

const uint8_t led_pins[LED_COUNT] = {13, 14, 15, 16, 17};

void leds_init(void) {
  for (int i = 0; i < LED_COUNT; i++) {
    gpio_init(led_pins[i]);
    gpio_set_dir(led_pins[i], GPIO_OUT);
    gpio_put(led_pins[i], 0);
  }
}

static bool led_pin(const trilog_value_t *in, uint *pin) {
  if (in[0].i < 0 || in[0].i >= LED_COUNT)
    return false;
  *pin = led_pins[in[0].i];
  return true;
}

static bool led_on(trilog_t *t, void *ud, const trilog_value_t *in,
                   trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  uint pin;
  if (!led_pin(in, &pin))
    return false;
  gpio_put(pin, 1);
  return true;
}

static bool led_off(trilog_t *t, void *ud, const trilog_value_t *in,
                    trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  uint pin;
  if (!led_pin(in, &pin))
    return false;
  gpio_put(pin, 0);
  return true;
}

static bool led_toggle(trilog_t *t, void *ud, const trilog_value_t *in,
                       trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  uint pin;
  if (!led_pin(in, &pin))
    return false;
  gpio_xor_mask(1u << pin);
  return true;
}

static bool sleep_for(trilog_t *t, void *ud, const trilog_value_t *in,
                      trilog_value_t *out) {
  (void)t, (void)ud, (void)out;
  if (in[0].i > 0)
    sleep_ms((uint32_t)in[0].i);
  return true;
}

void leds_register(trilog_t *t) {
  trilog_register(t, "led_on", "i", led_on, NULL);
  trilog_register(t, "led_off", "i", led_off, NULL);
  trilog_register(t, "led_toggle", "i", led_toggle, NULL);
  trilog_register(t, "sleep_ms", "i", sleep_for, NULL);
}
