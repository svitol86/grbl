#ifndef timer_h
#define timer_h

#ifdef PLASMA_THC
    volatile unsigned long millis_timer;    // Count Timer Interruptions (1ms)
    void timer_setup();                     // Setup Timer2 to fire every 1ms

#endif
#endif
