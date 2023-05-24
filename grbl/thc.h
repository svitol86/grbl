/**
 *  thc.h THC control
 * */

#ifndef thc_h
#define thc_h

#ifdef PLASMA_THC
    typedef struct {
        bool thc_enabled;
        uint8_t arc_retries;
        uint8_t arc_voltage_setpoint;
        uint8_t arc_voltage_hysteresis;
        uint8_t vad_threshold;
        float arc_fail_timeout;
        float arc_retry_delay;
        float pause_at_end;    
        float thc_delay;
        float arc_voltage_scale;
        float arc_voltage_offset;
    } plasma_settings_t;

    typedef struct {
        float arc_voltage;
        bool torch_on;
        bool arc_ok;
        bool thc_enabled;                   // THC working state
        bool vad_lock;
        bool void_lock;
        uint32_t thc_delay;
        volatile bool jog_z_up;		        // Torch must be rised
        volatile bool jog_z_down;	        // Torch must be move down 
    } plasma_state_t;
    plasma_state_t plasma;

    void plasma_init();
    void plasma_start();
    void plasma_stop();
    void plasma_update();

#endif

#endif