/**
 *  thc.c THC control
 * */
#include "grbl.h"

#ifdef PLASMA_THC
plan_block_t *current_block;
float analogSetVal;

// THC Initialize
void plasma_init()
{

  ARC_OK_DDR &= ~(ARC_OK_MASK); // Configure as input pins
#ifdef DISABLE_ARC_OK_PIN_PULL_UP
  ARC_OK_PORT &= ~(ARC_OK_MASK); // Normal low operation. Requires external pull-down.
#else
  ARC_OK_PORT |= ARC_OK_MASK; // Enable internal pull-up resistors. Normal high operation.
#endif

  plasma.jog_z_up = false;
  plasma.jog_z_down = false;
  ;
}

void plasma_start()
{

  uint8_t retries = settings.plasma.arc_retries;
  float arc_fail_timeout;

  do
  {
    spindle_start();
    plasma.torch_on = true;
    report_feedback_message(MESSAGE_PLASMA_TORCH_ON);
    arc_fail_timeout = settings.plasma.arc_fail_timeout;

    if (settings.plasma.arc_retries > 0)
    {
      do
      {
        delay_sec(0.1f, DELAY_MODE_SYS_SUSPEND);
        plasma.arc_ok = bit_isfalse(ARC_OK_PIN, ARC_OK_MASK);
        arc_fail_timeout -= 0.1f;
      } while ((!plasma.arc_ok) && (arc_fail_timeout >= 0.0f));
    }
    else
    {
      plasma.arc_ok = true;
    }

    if (plasma.arc_ok)
    {
      report_feedback_message(MESSAGE_PLASMA_ARC_OK);
      plasma.thc_delay = millis_timer + (uint32_t)ceilf(1000.0f * settings.plasma.thc_delay * 8);
      retries = 0;
    }
    else if (--retries > 0)
    {
      plasma.torch_on = false;
      spindle_stop();
      report_feedback_message(MESSAGE_PLASMA_ARC_RETRY);
      delay_sec(settings.plasma.arc_retry_delay, DELAY_MODE_SYS_SUSPEND);
    }
    else
    {
      plasma.torch_on = false;
      spindle_stop();
      report_feedback_message(MESSAGE_PLASMA_ARC_FAILED);
      pause_on_error(); // output message and enter similar state as tool change state (allow jogging before resume)
    }

  } while (retries);
}

void plasma_stop()
{
  if (!plasma.torch_on)
    return;

  if (settings.plasma.pause_at_end > 0.0f)
    delay_sec(settings.plasma.pause_at_end, DELAY_MODE_SYS_SUSPEND);

  spindle_stop();
  plasma.torch_on = plasma.arc_ok = plasma.thc_enabled = plasma.vad_lock = plasma.void_lock = false;
}

// THC Control
void plasma_update()
{

  //Calculate arc voltage value
  float arc_voltage = (analogVal / 1024.0 * settings.plasma.arc_voltage_scale) + settings.plasma.arc_voltage_offset;
  if (arc_voltage < 0)  { plasma.arc_voltage = 0; }
  else if (arc_voltage > UINT8_MAX)  { plasma.arc_voltage = UINT8_MAX; }
  else { plasma.arc_voltage = (uint8_t)arc_voltage; }

  if (!settings.plasma.thc_enabled)
  {
    plasma.thc_enabled = plasma.jog_z_up = plasma.jog_z_down = false;
    return;
  }
  
  // THC enabled afeter initial delay from arc ok signal
  if (plasma.arc_ok && millis_timer > plasma.thc_delay && !plasma.thc_enabled)
  {
    plasma.thc_enabled = true;
    report_feedback_message(MESSAGE_PLASMA_THC_ENABLED);
  }

  // Get planned rate for current movement
  current_block = plan_get_current_block();
  if (plasma.thc_enabled && current_block &&
      // st_get_realtime_rate() < (current_block->programmed_rate * (float)sys.f_override * (float)settings.plasma.vad_threshold / 10000.0 ))
      st_get_realtime_rate() < (current_block->programmed_rate * (float)settings.plasma.vad_threshold / 100.0))
  {
    plasma.vad_lock = true;
  }

  if (plasma.thc_enabled && current_block &&
      // st_get_realtime_rate() > (current_block->programmed_rate *  (float)sys.f_override / 100 * 0.99))
      st_get_realtime_rate() > (current_block->programmed_rate * 0.99))
  {
    plasma.vad_lock = false;
  }

  // Skip if THC isn't on
  if (!plasma.thc_enabled || plasma.vad_lock || plasma.void_lock ||
      (plasma.arc_voltage > (settings.plasma.arc_voltage_setpoint - settings.plasma.arc_voltage_hysteresis) &&
       plasma.arc_voltage < (settings.plasma.arc_voltage_setpoint + settings.plasma.arc_voltage_hysteresis))) // We are within our ok range
  {
    plasma.jog_z_up = false;
    plasma.jog_z_down = false;
  }
  else // We are not in range and need to deterimine direction needed to put us in range
  {
    if (plasma.arc_voltage > settings.plasma.arc_voltage_setpoint) // Torch is too high
    {
      plasma.jog_z_up = false;
      plasma.jog_z_down = true;
    }
    else // Torch is too low
    {
      plasma.jog_z_up = true;
      plasma.jog_z_down = false;
    }
  }
}

void pause_on_error()
{
  // system_set_exec_state_flag(EXEC_FEED_HOLD);   // Set up program pause for manual tool change
  system_set_exec_alarm(EXEC_ALARM_PLASMA_TORCH_ARC_FAILED);
  protocol_execute_realtime(); // Execute...
}

void report_string(const char *s)
{
  printPgmString(PSTR("[MSG:"));
  printPgmString(s);
  serial_write(']');
  printPgmString(PSTR("\r\n"));
}

#endif