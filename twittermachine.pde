/*
 * Twypper
 * http://tinkerlog.com
 *
 * \u00e4 = ä
 * \u00f6 = ö
 * \u00fc = ü 
 * \u00c4 = Ä
 * \u00d6 = Ö
 * \u00dc = Ü
 */
#include <Ethernet.h>
#include <avr/pgmspace.h>
#include "font.h"

// ethernet shield vars
byte mac[] = {0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED};   // mac adress
byte ip[] = {192, 168, 2, 2};                        // this ip 
byte gateway[] = {192, 168, 2, 1};                   // gateway
byte subnet[] = {255, 255, 255, 0};                  // subnet
byte server[] = {128, 121, 146, 235};                // search.twitter.com

char* search = "/search.json?q=it-gipfel&since_id=";  // the search request
char maxId[11] = "0";                                // since_id
char buf[180];        // buffer for parsing json
byte firstRun = 1;    // mark the first run
int tweetCount = 0;
byte charCount = 0;

// pins for interfacing the typewriter
byte clockPin = 2;    // SHCK pin 11 on 74595
byte storePin = 3;    // STCK pin 12 on 74595
byte enablePin = 4;   // OE pin 13 on 74595
byte dataPin = 5;     // DS pin 14 on 74595
byte in1 = 6;         // trigger pin

#define LOW_DELAY 158
#define PHASE_DELAY 158
#define PRINT_DELAY 100
#define MAX_LENGTH 62

void setup() {
  Ethernet.begin(mac, ip, gateway, subnet);
  Serial.begin(19200);  
  Serial.println("---");  
  pinMode(in1, INPUT);
  pinMode(clockPin, OUTPUT);
  pinMode(storePin, OUTPUT);
  pinMode(enablePin, OUTPUT);
  pinMode(dataPin, OUTPUT);
  digitalWrite(enablePin, HIGH);
  delay(1000);  
}


//--- parse json response -------------------------------------------------

/*
 * Skip all headers of the HTTP response.
 */ 
void skipHeaders(Client client) {
  char c[4];
  while (client.connected()) {
    if (client.available()) {
      c[3] = c[2];
      c[2] = c[1];
      c[1] = c[0];
      c[0] = client.read();
      // Serial.print(c[0]);
      if ((c[0] == 0x0a) && (c[1] == 0x0d) && (c[2] == 0x0a) && (c[3] == 0x0d)) {
        return;
      }
    }
  }  
}



/*
 * Reads a char of the client.
 * Returns -1 if the client is no longer connected.
 */
int readChar(Client client) {
  int c = -1;
  while (client.connected()) {
    if (client.available()) {
      c = client.read();
      break;
    }
  }
  return c;
}



/*
 * Reads until one of the matching chars is found.
 */
int readMatchingChar(Client client, char *match) {
  int c = -1;
  while (!strchr(match, c)) {
    c = readChar(client);
    if (c == -1) break;
  } 
  return c;
}



/*
 * Skips the string until the given char is found.
 */
void skip(Client client, char match) {
  // Serial.println("SKIP");
  int c = 0;
  while (true) {
    c = readChar(client);
    // Serial.print(c);
    if ((c == match) || (c == -1)) {
      break;
    }
  }
}



/*
 * Reads a token from the given string. Token is seperated by the 
 * given delimiter.
 */
int readToken(Client client, char *buf, char *delimiters) {
  int c = 0;
  while (true) {
    c = readChar(client);
    if (strchr(delimiters, c) || (c == -1)) {
      break;
    }
    *buf++ = c;
  }
  *buf = '\0';
  return c;
}



/*
 * Reads a json string.
 */
void readString(Client client, char *s) {
  int c, c1 = 0;
  // Serial.println("READS");
  while (c != -1) {
    c1 = c;
    c = readChar(client);
    if ((c == '"') && (c1 != '\\')) {
      break;
    }
    *s++ = c;
  }
  *s = 0;
}



/*
 * Reads a json value. Value is returned in buf.
 */
int readValue(Client client, char *buf) {
  int c;
  // Serial.println("READV");
  skip(client, ':');
  c = readChar(client);
  if (c == '"') {
    readString(client, buf);
    // Serial.println(buf);
    c = readChar(client);
  }
  else {
    *buf++ = c;
    c = readToken(client, buf, ",}");
    // Serial.println(buf);
  }
  return c;
}



#define STATE_NONE 0
#define STATE_KEY 1
#define STATE_RESULTS 2
#define STATE_TWEET 3
#define STATE_IN_RESULTS 4

/*
 * Reads and parses the json response.
 * Found tweets are written to the keyboard of the typewriter.
 */ 
void readResponse(Client client) {
  // Serial.println("headers");
  skipHeaders(client);
  skip(client, '{');
  byte state = STATE_KEY;
  char c, last_c = 0;
  while (client.connected()) {
    if (client.available()) {
      switch (state) {
        case STATE_KEY:
	  skip(client, '"');
	  readString(client, buf);
	  // Serial.print("key1:");
	  // Serial.println(buf);
	  if (strstr(buf, "results")) {
	    skip(client, '[');
	    state = STATE_RESULTS;
	  }
          else if (strstr(buf, "max_id")) {
	    c = readValue(client, maxId);            
            Serial.print("MAXID:");
            Serial.println(maxId);
          }
	  else {
	    c = readValue(client, buf);
	    // Serial.print("val1:");
	    // Serial.println(buf);
	    if (c == '}') {
	      state = STATE_NONE;
	      // Serial.println("done");
	    }
	  }
          break;
        case STATE_RESULTS:
	  // Serial.println("RES");
	  c = readMatchingChar(client, "{]");
	  if (c == ']') {
	    skip(client, ',');
	    state = STATE_KEY;
	  }
	  else if (c == '{') {
	    state = STATE_TWEET;
	    // Serial.println("TWEET");
	  }
	  else 
          break;
        case STATE_TWEET:
	  skip(client, '"');
	  readString(client, buf);
	  // Serial.print("key2:");
	  // Serial.println(buf);
	  if (strcmp(buf, "from_user") == 0) {
	    Serial.print("u:");            
	    // c = readValue(client, user);
	    // Serial.println(user);
	    c = readValue(client, buf);
	    Serial.println(buf);
            if (!firstRun) {
              printMessage(buf);             // print the user
              printMessage(" says: ");
            }
	  }
	  else if (strstr(buf, "text")) {
	    Serial.print("t:");
	    // c = readValue(client, tweet);
	    // Serial.println(tweet);
	    c = readValue(client, buf);
	    Serial.println(buf);
            if (!firstRun) {
              printMessage(buf);             // print the tweet
              sendChar(6, 8);
              sendChar(6, 8);
              charCount = 0;
            }
            tweetCount++;
	  }
	  else {
	    c = readValue(client, buf);
	  }
	  if (c == '}') {
	    state = STATE_IN_RESULTS;
	  }
	  break;
        case STATE_IN_RESULTS:
	  c = readMatchingChar(client, ",]");
	  // Serial.println(c);
	  if (c == ']') {
	    state = STATE_KEY;
	  }
	  else if (c == ',') {
	    skip(client, '{');
	    state = STATE_TWEET;
	    // Serial.println("TWEET");
	  }
	  break;
        default:
          ;
      }
    }
  }
  Serial.print(tweetCount);
  Serial.println(" tweets");
}


//--- interface with the typewriter --------------------------------------------

/*
 * Writes the given byte to the serial shift register
 */
void writeSerialByte(byte b) {
  digitalWrite(storePin, LOW);
  shiftOut(dataPin, clockPin, LSBFIRST, b);   
  digitalWrite(storePin, HIGH);
}



/*
 * Waits for the scan trigger at the given byte position and then
 * activates the output of the register.
 */
void scanInByte(byte b) {
  unsigned long time;
  byte repeat = 5;
  
  
  while (!digitalRead(in1));          // wait for HIGH
  while (repeat--) {
    while (digitalRead(in1));         // wait for trigger on the first line
    time = micros();
    time += PHASE_DELAY * b;          // compute the slot
    while (micros() < time);          // wait for the right slot
    digitalWrite(enablePin, LOW);     // enable output of the register 
    time += LOW_DELAY;                
    while (micros() < time);          // wait 
    digitalWrite(enablePin, HIGH);     // diable output of the register
  }
}



/*
 * Sends inbyte and outbyte scan codes
 */
void sendChar(byte inByte, byte outByte) {
  byte outMask;  
  // write one byte to the serial shift register
  outMask = 0x01 << (outByte-1);
  writeSerialByte(~outMask);  
  // scan on the in port and enable the register
  scanInByte(inByte-1);  
  delay(PRINT_DELAY);
}



/*
 * Sends the given char to the keyboard
 */
void printChar(byte c) {
  byte extraByte, inByte, outByte;
  if (c == 0x0D) {      // CR
    sendChar(6, 8);
  }
  else if (c == '@') {  // fake a '@'
    printChar('O');
    sendChar(1, 7);
    printChar('a');
  }
  else if ((c < 0x20) || (c > 0x84)) {
    Serial.print("special char:");
    Serial.println(c, DEC);
  }
  else {
    Serial.print("char: ");    Serial.print(c);    Serial.print(" ");  
    c -= 0x20;  
    // read three bytes from ascii table
    extraByte = pgm_read_byte_near(asciiTable + c*3);
    inByte = pgm_read_byte_near(asciiTable + c*3 + 1);
    outByte = pgm_read_byte_near(asciiTable + c*3 + 2);
    Serial.print(extraByte, DEC);    Serial.print(" ");
    Serial.print(inByte, DEC);       Serial.print(" ");
    Serial.println(outByte, DEC);
    if (extraByte == 1) {
      sendChar(5, 1);      // caps
    }
    sendChar(inByte, outByte);  
    if (extraByte == 1) {
      sendChar(6, 7);      // shift
    }
  }
}


#define STATE_0  0
#define STATE_U  1
#define STATE_01 2
#define STATE_02 3
#define STATE_3  4
#define STATE_E  5
#define STATE_F  6
#define STATE_C  7
#define STATE_D  8

/*
 * Takes care of german umlauts.
 * \u00e4 = ä
 * \u00f6 = ö
 * \u00fc = ü 
 * \u00c4 = Ä
 * \u00d6 = Ö
 * \u00dc = Ü
 */
void printMessage(char *msg) {
  char c;
  byte state = STATE_0;
  while (*msg != 0) {
    c = *msg;
    *msg++;
    if (c == '\\') {
      state = STATE_U;
      // Serial.println("backslash");
      continue;
    }
    
    switch (state) {
      case STATE_U:
        state = (c == 'u') ? STATE_01 : STATE_0;
        // Serial.println("->u");
        // Serial.println(c);
        // Serial.println(state, DEC);
        break;
      case STATE_01:
        state = (c == '0') ? STATE_02 : STATE_0;
        break;
      case STATE_02:
        state = (c == '0') ? STATE_3 : STATE_0;
        break;
      case STATE_3:
        switch (c) {
          case 'e' : state = STATE_E; break;
          case 'f' : state = STATE_F; break;
          case 'c' : state = STATE_C; break;
          case 'd' : state = STATE_D; break;
          default: state = STATE_0;
        }
        break;
      case STATE_E:
        if (c == '4') {
          c = 0x7F;      // ä
        }
        state = STATE_0;
        break;
      case STATE_F:
        if (c == '6') {
          c = 0x80;     // ö
        }
        else if (c == 'c') {
          c = 0x81;     // ü
        }
        state = STATE_0;
        break;
      case STATE_C:
        if (c == '4') {
          c = 0x82;     // Ä
          // Serial.println("Ae");
        }
        state = STATE_0;
        break;
      case STATE_D:
        if (c == '6') {
          c = 0x83;     // Ö
          // Serial.println("Oe");
        }
        else if (c == 'c') {
          c = 0x84;     // Ü
          // Serial.println("Ue");
        }
        state = STATE_0;
        break;
    }
    // Serial.print("state:");
    // Serial.println(state, DEC);
    
    if (state == STATE_0) {    
      printChar(c);
      // Serial.print("print:");
      // Serial.println(c);
      if (charCount++ == MAX_LENGTH) {
        sendChar(6, 8);      
        charCount = 0;      
      }
    }
  }  
}



void loop() {
  // if (firstRun) {
  //   printMessage("dies ist ein test mit \\u00e4 \\u00f6 \\u00fc \\u00c4\\u00d6\\u00dc");
  //   firstRun = 0;
  // }
  
  Serial.println("\nconnecting ...");
  Client client(server, 80);
  if (client.connect()) {
    Serial.println("ok");
    client.print("GET ");
    client.print(search);
    client.print(maxId);
    client.println(" HTTP/1.0");
    client.println();
    readResponse(client);
    Serial.println("disconnecting");
    client.stop();
    if (tweetCount > 0) {
      firstRun = 0;
      tweetCount = 0;
    }
  } 
  else {
    Serial.println("failed");
  }
  Serial.println("wait");  
  delay(60000);  

}

