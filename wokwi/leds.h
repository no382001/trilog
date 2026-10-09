#pragma once
#include "trilog.h"
#include <stdint.h>

#define LED_COUNT 5
extern const uint8_t led_pins[LED_COUNT];

void leds_init(void);
void leds_register(trilog_t *t);
