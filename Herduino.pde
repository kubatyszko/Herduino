#include <avr/sleep.h>
#include <avr/wdt.h>


#ifndef cbi
#define cbi(sfr, bit) (_SFR_BYTE(sfr) &= ~_BV(bit))
#endif
#ifndef sbi
#define sbi(sfr, bit) (_SFR_BYTE(sfr) |= _BV(bit))
#endif

#define INTERVAL1   9000000   // 2.5 hours , those values are in MILLISECONDS
#define INTERVAL2   1800000   // 30 mins
#define INTERVAL3    900000   // 15 mins

#define pinOutBuzzer  9       // buzzer on pin9
#define pinInIR 2             // input pin for IR sensor (pin2 supports interrupts)
#define pinOutSystem 6        // 6 - systemON LED via resistor
#define pinOutDevice1 3       // 3 - SSR directly
#define pinOutDevice2 4       // 4 - SSR directly
#define pinOutDevice3 5       // 5 - SSR directly

int start_bit = 2000;	      // Start bit threshold (Microseconds)
int bin_1 = 1000;	      // Binary 1 threshold (Microseconds)
int bin_0 = 400;	      // Binary 0 threshold (Microseconds)
int longpulse=1;              // If longpulse==0 it means pulseIn() timed out
long previousMillis=0;        // For tracking time elapsed without any sleep's
long interval=INTERVAL1;      // 2.5 hours is our initial timer value.
int timerType=1;              // 1 

short systemState=LOW;        // by default we start with LOW states - all OFF.
short device1State=LOW;       // by default we start with LOW states - all OFF.
short device2State=LOW;       // by default we start with LOW states - all OFF.
short device3State=LOW;       // by default we start with LOW states - all OFF.

long lastChangeTime=0;        // Required for button debouncing

long debounceDelay=1000;      // (IR debounce) - allow button change once per 1 second (to protect my appleTV's hard drive :) )


volatile byte remoteOn = 0;   // ==1, means remote has been pressed

volatile boolean f_wdt=0;     // interrupted

void setup() {

  pinMode(pinInIR, INPUT);    // only IR is input, all the rest are outputs
  pinMode(pinOutBuzzer, OUTPUT);
  pinMode(pinOutSystem, OUTPUT);
  pinMode(pinOutDevice1, OUTPUT);
  pinMode(pinOutDevice2, OUTPUT);
  pinMode(pinOutDevice3, OUTPUT);
  digitalWrite(pinInIR, HIGH);	//Pull up, then we won't need resistor on the IR input.

  MCUSR &= ~(1<<WDRF);
  // start timed sequence
  WDTCSR |= (1<<WDCE) | (0<<WDIE) | (1<<WDE);
  // set new watchdog timeout value
  WDTCSR = (1<<WDP3) | (0<<WDP2) | (0<<WDP2) | (1<<WDP0); // Setting watchdog to 8 seconds, refer to Atmel's doc for value table.
  WDTCSR |= _BV(WDIE);

  cbi( SMCR,SE );      // sleep enable, power down mode
  cbi( SMCR,SM0 );     // power down mode
  sbi( SMCR,SM1 );     // power down mode
  cbi( SMCR,SM2 );     // power down mode

}

void loop() {

  updateOutputs();

  while (remoteOn==1)
  {
    int key = getIRKey();      // If you're setting up new remote, place Serial.println(key) below to find out your keycodes.
    if (key==1301){            //1301 is my Power ON key
      if (lastChangeTime+debounceDelay < millis()){  // ensure that we won't capture more than one press per interval
        systemState=!systemState;                    // swap system state
        setupTimer();                                // if we turn on - set up the timer again.
        if (!systemState) {                          // if if we're turning off - switch everything OFF.
          device2State=systemState=device1State=device3State=LOW;
        }
        if (systemState)                             // and beep to confirm
        {
          singleBeep();
        }
        else{
          doubleBeep();
        }

        resetTimer();                                // if we turn off - reset the timer.
        updateOutputs();
        lastChangeTime=millis();
      }
    }
    if (key==149){                                  //First device
      if (lastChangeTime+debounceDelay < millis()){
        device1State=!(device1State) & systemState;
        if (device1State)
          singleBeep();
        else
          doubleBeep();
        updateOutputs();
        lastChangeTime=millis();
      }
    }
    if (key==1291){                                  //Second device
      if (lastChangeTime+debounceDelay < millis()){
        device2State=!(device2State) & systemState;
        if (device2State)
          singleBeep();
        else
          doubleBeep();
        updateOutputs();
        lastChangeTime=millis();
      }
    }
    if (key==1330){                                  //Third device
      if (lastChangeTime+debounceDelay < millis()){
        device3State=!(device3State) & systemState;
        if (device3State)
          singleBeep();
        else
          doubleBeep();
        updateOutputs();
        lastChangeTime=millis();
      }
    }
        if (key==1379 && systemState){             // This is my snooze button - it adds interval3 to current timer setting
      if (lastChangeTime+debounceDelay < millis()){
        singleBeep();
        interval+=INTERVAL3;
        lastChangeTime=millis();
      }
    }

    remoteOn=0;                                  //reset flag
    longpulse=1;                                  //reset longpulse
  }

  checkTimer();

  attachInterrupt (0, remoting, RISING);          //make sure IR sensor is on the interrupt

  system_sleep();                                // and try to go to sleep to save power
}

int getIRKey() {
  int data[12];
  while((longpulse=pulseIn(pinInIR, LOW)) < 2200)
  {
    if(longpulse==0) // if timed out
    {
      break;
    }
  }

  data[0] = pulseIn(pinInIR, LOW);      //Start measuring bits, I only want low pulses
  data[1] = pulseIn(pinInIR, LOW);
  data[2] = pulseIn(pinInIR, LOW);
  data[3] = pulseIn(pinInIR, LOW);
  data[4] = pulseIn(pinInIR, LOW);
  data[5] = pulseIn(pinInIR, LOW);
  data[6] = pulseIn(pinInIR, LOW);
  data[7] = pulseIn(pinInIR, LOW);
  data[8] = pulseIn(pinInIR, LOW);
  data[9] = pulseIn(pinInIR, LOW);
  data[10] = pulseIn(pinInIR, LOW);
  data[11] = pulseIn(pinInIR, LOW);

  delay(50); // to slow down the loop if needed

  for(int i=0;i<11;i++) {		  //Parse them
    if(data[i] > bin_1) {		  //is it a 1?
      data[i] = 1;
    }  
    else {
      if(data[i] > bin_0) {		//is it a 0?
        data[i] = 0;
      } 
      else {
        data[i] = 2;			  //Flag the data as invalid; I don't know what it is!
      }
    }
  }

  for(int i=0;i<11;i++) {		  //Pre-check data for errors
    if(data[i] > 1) {
      return -1;			     //Return -1 on invalid data
    }
  }

  int result = 0;
  int seed = 1;
  for(int i=0;i<11;i++) {		  //Convert bits to integer
    if(data[i] == 1) {
      result += seed;
    }
    seed = seed * 2;
  }
  return result;			     //Return key number
}

ISR(WDT_vect) {
  f_wdt=!f_wdt;  // set global flag
  //f_wdt=1;
  remoteOn=1;
}

void remoting()  // The ISR
{
  f_wdt=!f_wdt;  // set global flag
  remoteOn=1;
}

void resetTimer(){
  if (!systemState) { // reset only when the system is already OFF.
    previousMillis=0;
    interval=INTERVAL1;
    timerType=1;
  }
}

void setupTimer(){
  if (systemState) { // setup only when the system is already OFF.
    previousMillis=millis();
    interval=INTERVAL1;
    timerType=1;
  }
}

void checkTimer(){

  if (systemState && (millis() - previousMillis > interval)){ //will not check timer if the system is OFF
    previousMillis=millis();
    if (timerType==1){
      timerEvent1();             // give 2.5 hours warning, set interval to 30 minutes
      interval=INTERVAL2;
      timerType=2;
    }
    else
      if(timerType==2){ //30 minutes from now - beep, and set the timer to 15 min
        timerEvent2();
        timerType=3;
        interval=INTERVAL3;

      }
      else
        if(timerType==3){ //15 minutes from now - shut down.
          timerEvent3();
          device3State=device2State=device1State=systemState=LOW;

          timerType=0; // timers off completely until power ON kicks IN.
          resetTimer();
        }
  }

}

void singleBeep(){ // timer approaching
  beep();
}

void doubleBeep(){ // timer approaching
  beep();
  beep();
}

void timerEvent1(){ // timer approaching, you have 30 minutes + 15 minutes left.
  beep();
  pause();
  pause();

  beep();
  pause();
  pause();

  beep();
  pause();
  pause();

  beep();
  pause();
  pause();

  beep();

}

void timerEvent2(){ // you have 15 more minutes
  beep();
  beep();
  pause();

  beep();
  beep();
  pause();

  beep();
  beep();
  pause();

  beep();
  beep();
  pause();

  beep();
  beep();

}

void timerEvent3(){ //shutting down
  beep();
  beep();
  beep();

  beep();
  beep();
  beep();
  pause();

  beep(); 
  beep();
  beep();

  beep();
  beep();
  beep();
  pause();

  beep();
  beep();
  beep();

}

void inline beep(){ //inline saves a few hundred bytes in the compiled code

  for (long i = 0; i < 2048 * 0.15; i++ )
  {
    // 1 / 2048Hz = 488uS, or 244uS high and 244uS low to create 50% duty cycle
    digitalWrite(pinOutBuzzer, HIGH);
    delayMicroseconds(244);
    digitalWrite(pinOutBuzzer, LOW);
    delayMicroseconds(244);
  }
}

void pause(){
  delay(250);
}


int updateOutputs(){                                         // this will pass the values to Relays.
  digitalWrite(pinOutSystem,systemState);
  digitalWrite(pinOutDevice1,device1State);
  digitalWrite(pinOutDevice2,device2State);
  digitalWrite(pinOutDevice3,device3State);

}


void system_sleep() {

  cbi(ADCSRA,ADEN);                    // switch Analog to Digitalconverter OFF, we won't need it :).

  set_sleep_mode(SLEEP_MODE_PWR_DOWN); // sleep mode is set here
  sleep_enable();

  sleep_mode();                        // System sleeps here

    sleep_disable();                     // System continues execution here when watchdog timed out 

}









