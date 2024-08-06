import processing.video.*;
import controlP5.*;
import processing.serial.*;
import java.util.*;
import java.time.*;

boolean STARTED = false;

/* SETTINGS BEGIN */

// Serial port to connect to
String serialPortName = "COM3";

// If you want to debug the plotter without using a real serial port set this to true
boolean mockupData = false;

//give a title to the telemetry system. 
final String title = "HE54-305 Engine";

/* SETTINGS END */

Capture cam;

ControlP5 cp5;

Serial serialPort; // Serial port object

//graph stuff
Graph chamberPresGraph = new Graph(0 + 128 / 2 + 20 / 2, 0 + 80 / 2 + 20 / 2, 960 / 2 - 40 / 2 - 200 / 2, 720 / 2 - 30 / 2 - 160 / 2, color(255));
Graph thrustGraph = new Graph(0 + 128 / 2 + 20 / 2, 720 / 2 + 80 / 2 + 10 / 2, 960 / 2 - 40 / 2 - 200 / 2, 720 / 2 - 20 / 2 - 160 / 2, color(255));
Graph impulseGraph = new Graph(0 + 128 / 2 + 20 / 2, 1420 / 2 + 80 / 2 + 10 / 2, 960 / 2 - 40 / 2 - 200 / 2, 720 / 2 - 20 / 2 - 160 / 2, color(255));
Graph IspGraph = new Graph(0 + 128 / 2 + 20 / 2, 1200 / 2 + 80 / 2 + 10 / 2, 960 / 2 - 40 / 2 - 200 / 2, 480 / 2 - 20 / 2 - 160 / 2, color(255));
Graph throttleGraph = new Graph(3200 / 2 + 128 / 2 + 20 / 2, 1200 / 2 + 80 / 2 + 10 / 2, 640 / 2 - 40 / 2 - 200 / 2, 480 / 2 - 20 / 2 - 160 / 2, color(255));

float[] thrustGraphValues = new float[255]; // 
float[] pressureGraphValues = new float[255]; // 
float[] throttleGraphValues = new float[255]; // 
float[] impulseGraphValues = new float[255];
float[] IspGraphValues = new float[255];
float[] timestamps = new float[255]; // timestamps from the arduino, [99] will be newest
//units are seconds. 
float[] timestampsGraph = new float[255];
color[] graphColors = new color[6];

//error, fired, and reset flags
boolean ERROR = false;
boolean FIRED = false;

// fonts
PFont arial48;
PFont arialBold76;
PFont consolas42;

//timing
OffsetTime now = OffsetTime.now(ZoneOffset.UTC);
OffsetTime nowLocal = OffsetTime.now();
OffsetTime nowMissionStart = OffsetTime.now(ZoneOffset.UTC);
OffsetTime nowSystemOn = OffsetTime.now(ZoneOffset.UTC);

//recording
PrintWriter out;

void setup() {
  fullScreen(1);
  background(#1e1e1e);
  
  // set line graph colors
  graphColors[0] = color(131, 255, 20);
  graphColors[1] = color(232, 158, 12);
  graphColors[2] = color(255, 0, 0);
  graphColors[3] = color(62, 12, 232);
  graphColors[4] = color(13, 255, 243);
  graphColors[5] = color(200, 46, 232);
  
  cp5 = new ControlP5(this);
  
  Arrays.fill(thrustGraphValues, 0);
  Arrays.fill(pressureGraphValues, 0);
  Arrays.fill(throttleGraphValues, 0);
  
  thrustGraph.yMax = 800;
  thrustGraph.GraphColor = graphColors[0];
  thrustGraph.Title = "Engine Thrust";
  thrustGraph.xLabel = "Time (s)";
  thrustGraph.yLabel = "Thrust (N)";

  chamberPresGraph.yMax = 1000;
  chamberPresGraph.GraphColor = graphColors[1];
  chamberPresGraph.Title = "Chamber Pressure";
  chamberPresGraph.xLabel = "Time (s)";
  chamberPresGraph.yLabel = "Pressure (psi)";
  
  throttleGraph.yMax = 100;
  throttleGraph.GraphColor = graphColors[2];
  throttleGraph.Title = "Oxidizer Throttle";
  throttleGraph.xLabel = "Time (s)";
  throttleGraph.yLabel = "Throttle (%)";
  
  impulseGraph.yMax = 100;
  impulseGraph.GraphColor = graphColors[4];
  impulseGraph.Title = "Total Impulse";
  impulseGraph.xLabel = "Time (s)";
  impulseGraph.yLabel = "Impulse (N∙s)";
  
  
  if (!mockupData) {
    //String serialPortName = Serial.list()[3];
    try {
      serialPort = new Serial(this, serialPortName, 115200);
    } catch (Exception e) {
      println(e);
      ERROR = true;
    }
  }
  else serialPort = null;

  String[] cameras = Capture.list();
  
  if (cameras.length == 0) {
    println("There are no cameras available for capture.");
  } else {
    println("Available cameras:");
    for (int i = 0; i < cameras.length; i++) {
      println(cameras[i]);
    }
    
    // The camera can be initialized directly using an 
    // element from the array returned by list():
    cam = new Capture(this, 2240 / 2, 1680 / 2, cameras[0]);
    cam.start();
  }
  
  arial48 = createFont("Arial", 48 / 2);
  arialBold76 = createFont("Arial Bold", 76 / 2);
  consolas42 = createFont("Consolas", 42 / 2);
  
  ControlFont buttonFont = new ControlFont(consolas42);
  cp5.addButton("reset")
     .setValue(0)
     .setPosition(3280 / 2, 710 / 2 + 20 / 2)
     .setSize(480 / 2, 80 / 2)
     .setFont(buttonFont)
     .updateSize()
     ;
  cp5.addButton("overrideRecord")
   .setValue(0)
   .setPosition(3280 / 2, 820 / 2)
   .setSize(480 / 2, 80 / 2)
   .setCaptionLabel("Override-start rec.")
   .setFont(buttonFont)
   .updateSize()
   ;

}

byte[] inBuffer = new byte[100]; // holds serial message
void draw() {
  STARTED = true;
  
  //update clock
  now = OffsetTime.now(ZoneOffset.UTC);
  if (!FIRED) {
    nowMissionStart = OffsetTime.now(ZoneOffset.UTC);
  }
  int nanoUTC = now.getNano();
  if (nanoUTC != 0) nanoUTC = Math.round(nanoUTC / 1000000.0);
  String UTC = String.format("%02d:%02d:%02d:%03d", now.getHour(), now.getMinute(), now.getSecond(), nanoUTC);
  nowLocal = OffsetTime.now();
  int nanoCLT = now.getNano();
  if (nanoCLT != 0) nanoCLT = Math.round(nanoCLT / 1000000.0);
  String CLT = String.format("%02d:%02d:%02d:%03d", nowLocal.getHour(), nowLocal.getMinute(), nowLocal.getSecond(), nanoCLT);
  
  Duration METDuration = Duration.between(nowMissionStart, now);
  int nanoMET = METDuration.getNano();
  if (nanoMET != 0) nanoMET = Math.round(nanoMET / 1000000.0);
  long secondsMET = METDuration.getSeconds();
  String MET = String.format("%02d:%02d:%02d:%03d", secondsMET / 3600 % 60, 
                              secondsMET / 60 % 60, 
                              secondsMET % 60, 
                              nanoMET);
  
  Duration SOTDuration = Duration.between(nowSystemOn, now);
  int nanoSOT = SOTDuration.getNano();
  if (nanoSOT != 0) nanoSOT = Math.round(nanoSOT / 1000000.0);
  long secondsSOT = SOTDuration.getSeconds();
  String SOT = String.format("%02d:%02d:%02d:%03d", secondsSOT / 3600 % 60, 
                              secondsSOT / 60 % 60, 
                              secondsSOT % 60, 
                              nanoSOT);
  
  /* Read serial and update values */
  if (!mockupData && serialPort == null) ERROR = true;
  if (mockupData || (serialPort != null && serialPort.available() > 0)) {
    String myString = "";
    if (!mockupData) {
      try {
        inBuffer = new byte[100];
        serialPort.readBytesUntil('\r', inBuffer);
      }
      catch (Exception e) {
        println("Failed to read serial");
        ERROR = true;
      }
      myString = new String(inBuffer);
    }
    else {
      myString = mockupSerialFunction();
    }
        
    // split the string at delimiter (space)
    String[] nums = split(myString, ' ');
    
    print(nums.length);
    
    if (nums.length == 5) {
    
    for (int i = 0; i < thrustGraphValues.length - 1; i++) {
      thrustGraphValues[i] = thrustGraphValues[i + 1];
    }
    if (nums[0].length() != 0) {
        thrustGraphValues[thrustGraphValues.length - 1] = Math.max(Float.parseFloat(nums[0]), 0);
    }
    
    for (int i = 0; i < pressureGraphValues.length - 1; i++) {
      pressureGraphValues[i] = pressureGraphValues[i + 1];
    }
    if (nums[1].length() != 0) {
      pressureGraphValues[pressureGraphValues.length - 1] = Float.parseFloat(nums[1]);
    }
    
    for (int i = 0; i < throttleGraphValues.length - 1; i++) {
      throttleGraphValues[i] = throttleGraphValues[i + 1];
    }
    if (nums[2].length() != 0) {
      throttleGraphValues[throttleGraphValues.length - 1] = Float.parseFloat(nums[2]);
    }
    
    
    //check if there is oxidizer flow by using throttle telemetry AND CREATE NEW FILE FOR RECORDING
    if (throttleGraphValues[throttleGraphValues.length - 1] > 0 && !FIRED) {
      FIRED = true;
      out = createWriter("recordings/" + year() + "-" + month() + "-" + day() + " " + now.getHour() + "-" + now.getMinute() + "-" + now.getSecond() + ".txt");
    }
    
    for (int i = 0; i < timestamps.length - 1; i++) {
      timestamps[i] = timestamps[i + 1];
    }
    if (nums[3].length() != 0) {
      timestamps[timestamps.length - 1] = Float.parseFloat(nums[3]);
    }
    }
    
    for (int i = timestamps.length - 1; i >= 0; i--) {
      timestampsGraph[i] = (timestamps[i] - timestamps[timestamps.length - 1]);
      if (timestampsGraph[i] < -10000) {
        timestampsGraph[i] = -10000;
        if (i < timestamps.length - 1) {
          thrustGraphValues[i] = thrustGraphValues[i + 1];
          pressureGraphValues[i] = pressureGraphValues[i + 1];
          throttleGraphValues[i] = throttleGraphValues[i + 1];
        }
      }
    }
    
    timestampsGraph[0] = -10000; // ensures that the graph is always to scale, but there might be a little weird behaviour at the far end
    
    if (FIRED) { // things to do if the engine has been fired, like record data and record the total impulse
      //calculate total impulse, Isp, mass flow rate approx., other parameters
      for (int i = 0; i < impulseGraphValues.length - 1; i++) {
        impulseGraphValues[i] = impulseGraphValues[i + 1];
      }
      if (timestampsGraph[timestampsGraph.length - 2] < 0.0) impulseGraphValues[impulseGraphValues.length - 1] += (-0.001 * thrustGraphValues[thrustGraphValues.length - 1] * timestampsGraph[timestampsGraph.length - 2]);
      impulseGraph.yMax = Math.max(impulseGraph.yMax, impulseGraphValues[impulseGraphValues.length - 1]);
      
      out.printf("MET: %s | Thrust: %5.2f | Chamber Pres: %5.2f | Throttle: %3.2f | Total Impulse: %.2f\n", MET,
                                      thrustGraphValues[thrustGraphValues.length - 1], 
                                      pressureGraphValues[pressureGraphValues.length - 1], 
                                      throttleGraphValues[throttleGraphValues.length - 1],
                                      impulseGraphValues[impulseGraphValues.length - 1]);
    } else {
      impulseGraph.yMax = 100;
      Arrays.fill(impulseGraphValues, 0);
    }
  }
  
  background(#1e1e1e);
  thrustGraph.DrawAxis();
  thrustGraph.LineGraph(timestampsGraph, thrustGraphValues);
  
  chamberPresGraph.DrawAxis();
  chamberPresGraph.LineGraph(timestampsGraph, pressureGraphValues);
  
  throttleGraph.DrawAxis();
  throttleGraph.LineGraph(timestampsGraph, throttleGraphValues);
  
  impulseGraph.DrawAxis();
  impulseGraph.LineGraph(timestampsGraph, impulseGraphValues);
    
  if (cam.available() == true) {
    cam.read();
  }
  //image(cam, 0, 0);
  // The following does the same, and is faster when just drawing the image
  // without any additional resizing, transformations, or tint.
  set(960 / 2, 480 / 2, cam);
  
  textAlign(CENTER);
  textFont(arialBold76);
  text(title, 3520 / 2, 100 / 2);
  textFont(arial48);
  text("Ground Control & Telemetry", 3520 / 2, 175 / 2);
  textFont(consolas42);
  text("CLT: " + CLT + "\nUTC: " + UTC + "\nSOT: " + SOT + "\nMET: " + MET, 3520 / 2, 250 / 2);
  
  fill(color(48)); stroke(200); strokeWeight(2);
  rect(3200 / 2 + 20 / 2, 480 / 2 + 10 / 2, 640 / 2 - 40 / 2, 720 / 2 - 20 / 2, 20 / 2, 20 / 2, 20 / 2, 20 / 2);
  //decide on color and text of status indicators
  color statusColor = color(#619fe1); String statusText = "Pre-Launch Standby";
  color recordingColor = color(#619fe1); String recText = "Auto-record Standby";
  if (ERROR) {
    statusText = "Software Error";
    statusColor = color(#ca2715);
  } else if (FIRED && throttleGraphValues[throttleGraphValues.length - 1] != 0) {
    statusText = "Firing: Throttle " + throttleGraphValues[throttleGraphValues.length - 1] + "%";
    statusColor = color(#ddcf0e);
    recText = "Recording";
    recordingColor = color(#ff0101);
  } else if (FIRED) {
    statusText = "Post-Launch Standby";
    statusColor = color(#4FD33E);
    recText = "Recording";
    recordingColor = color(#e68929);
  }
  
  strokeWeight(0); fill(statusColor);
  rect(3200 / 2 + 20 / 2 + 10 / 2, 480 / 2 + 10 / 2 + 10 / 2, 640 / 2 - 40 / 2 - 20 / 2, 100 / 2, 20 / 2, 20 / 2, 20 / 2, 20 / 2);
  textFont(arial48); fill(0);
  text(statusText, 3520 / 2, 565 / 2);
  fill(recordingColor);
  rect(3200 / 2 + 20 / 2 + 10 / 2, 480 / 2 + 10 / 2 + 10 / 2 + 110 / 2, 640 / 2 - 40 / 2 - 20 / 2, 100 / 2, 20 / 2, 20 / 2, 20 / 2, 20 / 2);
  textFont(arial48); fill(0);
  text(recText, 3520 / 2, 565 / 2 + 110 / 2);
  textFont(consolas42); fill(200);
  text("RESET", 3520 / 2, 770 / 2);
  
  
  fill(color(48)); stroke(200); strokeWeight(2);
  rect(3200 / 2 + 20 / 2, 1680 / 2 + 10 / 2, 640 / 2 - 40 / 2, 480 / 2 - 30 / 2, 20 / 2, 20 / 2, 20 / 2, 20 / 2);
  textFont(arial48); fill(200);
  text("Raw telemetry", 3520 / 2, 1680 / 2 + 68 / 2 / 2);
}

public void reset(int value) {
  if (!STARTED) return;
  println("Reset pressed");
  if (FIRED) {
    out.flush();
    out.close();
    Arrays.fill(impulseGraphValues, 0);
    FIRED = false;
  }
}
public void overrideRecord(int value) {
  if (!STARTED) return;
  println("Override - start record pressed");
  if (!FIRED) {
    FIRED = true;
    out = createWriter("recordings/" + year() + "-" + month() + "-" + day() + " " + now.getHour() + "-" + now.getMinute() + "-" + now.getSecond() + ".txt");
  }
}
