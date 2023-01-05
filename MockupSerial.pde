// If you want to debug the plotter without using a real serial port

int mockupValue = 0;
int mockupDirection = 10;
int cnter = 1000;

String mockupSerialFunction () {
  mockupValue = (mockupValue + mockupDirection);
  if (mockupValue > 100)
    mockupDirection = -10;
  else if (mockupValue < -100)
    mockupDirection = 10;
  String r = "";
  for (int i = 0; i<4; i++) {
    switch (i) {
      case 0:
        r += abs(mockupValue * 4 * sin(cnter))+" ";
        break;
      case 1:
        r += 100*cos(mockupValue*(2*3.14)/1000)+" ";
        break;
      case 2:
        int throttle = 0;
        //if (mockupValue >= 0) throttle = 100;
        //else throttle = 0;
        r += throttle+" ";
        break;
      case 3:
        r += cnter+" ";
        break;
    }
  }
  cnter += 40;
  r += '\r';
  delay(10);
  return r;
}
