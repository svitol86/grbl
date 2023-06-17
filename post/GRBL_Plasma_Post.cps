/*
   Custom Post-Processor for GRBL based Openbuilds-style CNC machines, router and laser-cutting
   Made possible by
   Swarfer  https://github.com/swarfer/GRBL-Post-Processor
   Sharmstr https://github.com/sharmstr/GRBL-Post-Processor
   Strooom  https://github.com/Strooom/GRBL-Post-Processor
   This post-Processor should work on GRBL-based machines

   Changelog
   22/Aug/2016 - V01     : Initial version (Stroom)
   23/Aug/2016 - V02     : Added Machining Time to Operations overview at file header (Stroom)
   24/Aug/2016 - V03     : Added extra user properties - further cleanup of unused variables (Stroom)
   07/Sep/2016 - V04     : Added support for INCHES. Added a safe retract at beginning of first section (Stroom)
   11/Oct/2016 - V05     : Update (Stroom)
   30/Jan/2017 - V06     : Modified capabilities to also allow waterjet, laser-cutting (Stroom)
   28 Jan 2018 - V07     : Fix arc errors and add gotoMCSatend option (Swarfer)
   16 Feb 2019 - V08     : Ensure X, Y, Z  output when linear differences are very small (Swarfer)
   27 Feb 2019 - V09     : Correct way to force word output for XYZIJK, see 'force:true' in CreateVariable (Swarfer)
   27 Feb 2018 - V10     : Added user properties for router type. Added rounding of dial settings to 1 decimal (Sharmstr)
   16 Mar 2019 - V11     : Added rounding of tool length to 2 decimals.  Added check for machine config in setup (Sharmstr)
                      : Changed RPM warning so it includes operation. Added multiple .nc file generation for tool changes (Sharmstr)
                      : Added check for duplicate tool numbers with different geometry (Sharmstr)
   17 Apr 2019 - V12     : Added check for minimum  feed rate.  Added file names to header when multiple are generated  (Sharmstr)
                      : Added a descriptive title to gotoMCSatend to better explain what it does.
                      : Moved machine vendor, model and control to user properties  (Sharmstr)
   15 Aug 2019 - V13     : Grouped properties for clarity  (Sharmstr)
   05 Jun 2020 - V14     : description and comment changes (Swarfer)
   09 Jun 2020 - V15     : remove limitation to MM units - will produce inch output but user must note that machinehomeX/Y/Z values are always MILLIMETERS (Swarfer)
   10 Jun 2020 - V1.0.16 : OpenBuilds-Fusion360-Postprocessor, Semantic Versioning, Automatically add router dial if Router type is set (OpenBuilds)
   11 Jun 2020 - V1.0.17 : Improved the header comments, code formatting, removed all tab chars, fixed multifile name extensions
   21 Jul 2020 - V1.0.18 : Combined with Laser post - will output laser file as if an extra tool.
   08 Aug 2020 - V1.0.19 : Fix for spindleondelay missing on subfiles
   02 Oct 2020 - V1.0.20 : Fix for long comments and new restrictions
   05 Nov 2020 - V1.0.21 : poweron/off for plasma, coolant can be turned on for laser/plasma too
   04 Dec 2020 - V1.0.22 : Add Router11 and dial settings
   16 Jan 2021 - V1.0.23 : Remove end of file marker '%' from end of output, arcs smaller than toolRadius will be linearized
   25 Jan 2021 - V1.0.24 : Improve coolant codes
   26 Jan 2021 - V1.0.25 : Plasma pierce height, and probe
   29 Aug 2021 - V1.0.26 : Regroup properties for display, Z height check options
   03 Sep 2021 - V1.0.27 : Fix arc ramps not changing Z when they should have
   12 Nov 2021 - V1.0.28 : Added property group names, fixed default router selection, now uses permittedCommentChars  (sharmstr)
   24 Nov 2021 - V1.0.28 : Improved coolant selection, tweaked property groups, tweaked G53 generation, links for help in comments.
   21 Feb 2022 - V1.0.29 : Fix sideeffects of drill operation having rapids even when in noRapid mode by always resetting haveRapid in onSection
   10 May 2022 - V1.0.30 : Change naming convention for first file in multifile output (Sharmstr)
   xx Sep 2022 - V1.0.31 : better laser, with pierce option if cutting
   06 Dec 2022 - V1.0.32 : fix long comments that were getting extra brackets
   22 Dec 2022 - V1.0.33 : refactored file naming and debugging, indented with astyle
   10 Mar 2023 - V1.0.34 : move coolant code to the spindle control line to help with restarts
   26 Mar 2023 - V1.0.35 : plasma pierce height override,  spindle speed change always with an M3, version number display
*/
obversion = 'V1.0.35_GMB';
description = "GRBL Plasma";  // cannot have brackets in comments
longDescription = description + " : Post" + obversion; // adds description to post library dialog box
vendor = "GMB";
model = "GRBL";
certificationLevel = 2;
minimumRevision = 45892;

debugMode = true;

extension = "gcode";                            // file extension of the gcode file
setCodePage("ascii");                           // character set of the gcode file
//setEOL(CRLF);                                 // end-of-line type : use CRLF for windows

var permittedCommentChars = " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,=_-*/\\:";
capabilities = CAPABILITY_MILLING | CAPABILITY_JET;      // intended for a CNC, so Milling, and waterjet/plasma/laser
tolerance = spatial(0.01, MM);
minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.125, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.1); // was 0.01
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = (1 << PLANE_XY);// | (1 << PLANE_ZX) | (1 << PLANE_YZ); // only XY, ZX, and YZ planes
// the above circular plane limitation appears to be a solution to the faulty arcs problem (but is not entirely)
// an alternative is to set EITHER minimumChordLength OR minimumCircularRadius to a much larger value, like 0.5mm

// user-defined properties : defaults are set, but they can be changed from a dialog box in Fusion when doing a post.
properties =
{
   machineHomeZ: -10,            // absolute machine coordinates where the machine will move to at the end of the job - first retracting Z, then moving home X Y
   machineHomeX: -10,            // always in millimeters
   machineHomeY: -10,
   gotoMCSatend: false,          // true will do G53 G0 x{machinehomeX} y{machinehomeY}, false will do G0 x{machinehomeX} y{machinehomeY} at end of program
   //plasma stuff
   plasma_usetouchoff: false,                        // use probe for touchoff if true
   plasma_touchoffOffset: 5.0,                       // offset from trigger point to real Z0, used in G10 line
   plasma_pierceHeightoverride: false,                // if true replace all pierce height settings with value below
   plasma_pierceHeightValue: toPreciseUnit(5, MM),   // not forcing mm, user beware
   plasma_cutHeightoverride: false,                // if true replace all cut height settings with value below
   plasma_cutHeightValue: toPreciseUnit(5, MM),   // not forcing mm, user beware
   plasma_probeDistance: 30,   // distance to probe down in Z, always in millimeters
   plasma_probeRate: 100,      // feedrate for probing, in mm/minute
   plasma_pierceDelayOverride: false, // override tool pierce delay
   plasma_pierceDelay: 1.0,       // pierce delay in s

   linearizeSmallArcs: true,     // arcs with radius < toolRadius have radius errors, linearize instead?
   machineVendor: "GMB",
   modelMachine: "Generic",
   machineControl: "Grbl 1.1 PLASMA",
};

// user-defined property definitions - note, do not skip any group numbers
groupDefinitions =
{
   //postInfo: {title: "OpenBuilds Post Documentation: https://docs.openbuilds.com/doku.php", description: "", order: 0},
   safety: { title: "Safety", description: "Safety options", order: 2 },
   startEndPos: { title: "Job Start Z and Job End X,Y,Z Coordinates", description: "Set the spindle start and end position", order: 4 },
   arcs: { title: "Arcs", description: "Arc options", order: 5 },
   plasma: { title: "Plasma", description: "Plasma options", order: 6 },
   machine: { title: "Machine", description: "Machine options", order: 7 }
};
propertyDefinitions =
{
   gotoMCSatend: {
      group: "startEndPos",
      title: "EndPos: Use Machine Coordinates (G53) at end of job?",
      description: "Yes will do G53 G0 x{machinehomeX} y(machinehomeY) (Machine Coordinates), No will do G0 x(machinehomeX) y(machinehomeY) (Work Coordinates) at end of program",
      type: "boolean",
   },
   machineHomeX: {
      group: "startEndPos",
      title: "EndPos: End of job X position (MM).",
      description: "(G53 or G54) X position to move to in Millimeters",
      type: "spatial",
   },
   machineHomeY: {
      group: "startEndPos",
      title: "EndPos: End of job Y position (MM).",
      description: "(G53 or G54) Y position to move to in Millimeters.",
      type: "spatial",
   },
   machineHomeZ: {
      group: "startEndPos",
      title: "startEndPos: START and End of job Z position (MCS Only) (MM)",
      description: "G53 Z position to move to in Millimeters, normally negative.  Moves to this distance below Z home.",
      type: "spatial",
   },

   linearizeSmallArcs: {
      group: "arcs",
      title: "ARCS: Linearize Small Arcs",
      description: "Arcs with radius < toolRadius can have mismatched radii, set this to Yes to linearize them. This solves G2/G3 radius mismatch errors.",
      type: "boolean",
   },

   plasma_usetouchoff: { title: "Use Z touchoff probe routine", description: "Set to true if have a touchoff probe for Plasma.", group: "plasma", type: "boolean" },
   plasma_touchoffOffset: { title: "Plasma touch probe offset", description: "Offset in Z at which the probe triggers, always Millimeters, always positive.", group: "plasma", type: "spatial" },
   plasma_pierceHeightoverride: { title: "Override the pierce height", description: "Set to true if want to always use the pierce height Z value.", group: "plasma", type: "boolean" },
   plasma_pierceHeightValue: { title: "Override the pierce height Z value", description: "Offset in Z for the plasma pierce height, always positive.", group: "plasma", type: "spatial" },
   plasma_cutHeightoverride: { title: "Override the cut height", description: "Set to true if want to always use the cut height Z value.", group: "plasma", type: "boolean" },
   plasma_cutHeightValue: { title: "Override the cut height Z value", description: "Offset in Z for the plasma cut height, always positive.", group: "plasma", type: "spatial" },
   plasma_probeDistance: { title: "Probe travel distance", description: "Distance to probe down in Z, always in millimeters", group: "plasma", type: "spatial" },
   plasma_probeRate: { title: "Probe travel rate", description: "Feedrate for probing, in mm/minute", group: "plasma", type: "integer" },
   plasma_pierceDelayOverride: { title: "Override pierce delay", description: "Set to true if want to always use the pierce delay value.", group: "plasma", type: "boolean" },
   plasma_pierceDelay: { title: "Override pierce delay value", description: "Pierce delay in s", group: "plasma", type: "number" },

   machineVendor: {
      group: "machine",
      title: "Machine Vendor",
      description: "Machine vendor defined here will be displayed in header if machine config not set.",
      type: "string",
   },
   modelMachine: {
      group: "machine",
      title: "Machine Model",
      description: "Machine model defined here will be displayed in header if machine config not set.",
      type: "string",
   },
   machineControl: {
      group: "machine",
      title: "Machine Control",
      description: "Machine control defined here will be displayed in header if machine config not set.",
      type: "string",
   }
};

// creation of all kinds of G-code formats - controls the amount of decimals used in the generated G-Code
var gFormat = createFormat({ prefix: "G", decimals: 0 });
var mFormat = createFormat({ prefix: "M", decimals: 0 });

var xyzFormat = createFormat({ decimals: (unit == MM ? 3 : 4) });
var abcFormat = createFormat({ decimals: 3, forceDecimal: true, scale: DEG });
var arcFormat = createFormat({ decimals: (unit == MM ? 3 : 4) });
var feedFormat = createFormat({ decimals: 0 });
var rpmFormat = createFormat({ decimals: 0 });
var secFormat = createFormat({ decimals: 1, forceDecimal: true }); // seconds
//var taperFormat = createFormat({decimals:1, scale:DEG});

var xOutput = createVariable({ prefix: "X", force: false }, xyzFormat);
var yOutput = createVariable({ prefix: "Y", force: false }, xyzFormat);
var zOutput = createVariable({ prefix: "Z", force: false }, xyzFormat); // dont need Z every time
var feedOutput = createVariable({ prefix: "F" }, feedFormat);
var sOutput = createVariable({ prefix: "S", force: false }, rpmFormat);
var mOutput = createVariable({ force: false }, mFormat); // only use for M3/4/5

// for arcs
var iOutput = createReferenceVariable({ prefix: "I", force: true }, arcFormat);
var jOutput = createReferenceVariable({ prefix: "J", force: true }, arcFormat);
var kOutput = createReferenceVariable({ prefix: "K", force: true }, arcFormat);

var gMotionModal = createModal({}, gFormat);                                  // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({ onchange: function () { gMotionModal.reset(); } }, gFormat); // modal group 2 // G17-19
var gAbsIncModal = createModal({}, gFormat);                                  // modal group 3 // G90-91
var gFeedModeModal = createModal({}, gFormat);                                // modal group 5 // G93-94
var gUnitModal = createModal({}, gFormat);                                    // modal group 6 // G20-21
var gWCSOutput = createModal({}, gFormat);                                    // for G54 G55 etc

var minimumFeedRate = toPreciseUnit(45, MM); // GRBL lower limit in mm/minute
var fileIndexFormat = createFormat({ width: 2, zeropad: true, decimals: 0 });

var Zmax = 0;
var workOffset = 0;
var haveRapid = false;  // assume no rapid moves
var powerOn = false;    // is the laser power on? used for laser when haveRapid=false
var retractHeight = 1;  // will be set by onParameter and used in onLinear to detect rapids
var clearanceHeight = 10;  // will be set by onParameter
var plasma_cutHeight = 1;      // set by onParameter
var leadinRate = 314;   // set by onParameter: the lead-in feedrate,plasma
var cuttingMode = 'none'; // set by onParameter for laser/plasma
var linmove = 1;        // linear move mode
var toolRadius;         // for arc linearization
var plasma_pierceHeight = 3.14; // set by onParameter from Linking|PierceClearance
var coolantIsOn = 0;    // set when coolant is used to we can do intelligent turn off
var currentworkOffset = 54; // the current WCS in use, so we can retract Z between sections if needed
var clnt = '';          // coolant code to add to spindle line
var probed = false;

function checkMinFeedrate(section, op) {
   var alertMsg = "";
   if (section.getParameter("operation:tool_feedCutting") < minimumFeedRate) {
      var alertMsg = "Cutting\n";
      //alert("Warning", "The cutting feedrate in " + op + "  is set below the minimum feedrate that grbl supports.");
   }

   if (section.getParameter("operation:tool_feedRetract") < minimumFeedRate) {
      var alertMsg = alertMsg + "Retract\n";
      //alert("Warning", "The retract feedrate in " + op + "  is set below the minimum feedrate that grbl supports.");
   }

   if (section.getParameter("operation:tool_feedEntry") < minimumFeedRate) {
      var alertMsg = alertMsg + "Entry\n";
      //alert("Warning", "The retract feedrate in " + op + "  is set below the minimum feedrate that grbl supports.");
   }

   if (section.getParameter("operation:tool_feedExit") < minimumFeedRate) {
      var alertMsg = alertMsg + "Exit\n";
      //alert("Warning", "The retract feedrate in " + op + "  is set below the minimum feedrate that grbl supports.");
   }

   if (section.getParameter("operation:tool_feedRamp") < minimumFeedRate) {
      var alertMsg = alertMsg + "Ramp\n";
      //alert("Warning", "The retract feedrate in " + op + "  is set below the minimum feedrate that grbl supports.");
   }

   if (section.getParameter("operation:tool_feedPlunge") < minimumFeedRate) {
      var alertMsg = alertMsg + "Plunge\n";
      //alert("Warning", "The retract feedrate in " + op + "  is set below the minimum feedrate that grbl supports.");
   }

   if (alertMsg != "") {
      var fF = createFormat({ decimals: 0, suffix: (unit == MM ? "mm" : "in") });
      var fo = createVariable({}, fF);
      alert("Warning", "The following feedrates in " + op + "  are set below the minimum feedrate that GRBL supports.  The feedrate should be higher than " + fo.format(minimumFeedRate) + " per minute.\n\n" + alertMsg);
   }
}

function writeBlock() {
   writeWords(arguments);
}

/**
   Thanks to nyccnc.com
   Thanks to the Autodesk Knowledge Network for help with this at
   https://knowledge.autodesk.com/support/hsm/learn-explore/caas/sfdcarticles/sfdcarticles/How-to-use-Manual-NC-options-to-manually-add-code-with-Fusion-360-HSM-CAM.html!
*/
function onPassThrough(text) {
   var commands = String(text).split(",");
   for (text in commands) {
      writeBlock(commands[text]);
   }
}

function myMachineConfig() {
   // 3. here you can set all the properties of your machine if you havent set up a machine config in CAM.  These are optional and only used to print in the header.
   myMachine = getMachineConfiguration();
   if (!myMachine.getVendor()) {
      // machine config not found so we'll use the info below
      myMachine.setWidth(600);
      myMachine.setDepth(800);
      myMachine.setHeight(130);
      myMachine.setMaximumSpindlePower(700);
      myMachine.setMaximumSpindleSpeed(30000);
      myMachine.setMilling(true);
      myMachine.setTurning(false);
      myMachine.setToolChanger(false);
      myMachine.setNumberOfTools(1);
      myMachine.setNumberOfWorkOffsets(6);
      myMachine.setVendor(properties.machineVendor);
      myMachine.setModel(properties.modelMachine);
      myMachine.setControl(properties.machineControl);
   }
}

// Remove special characters which could confuse GRBL : $, !, ~, ?, (, )
// In order to make it simple, I replace everything which is not A-Z, 0-9, space, : , .
// Finally put everything between () as this is the way GRBL & UGCS expect comments
function formatComment(text) {
   return ("(" + filterText(String(text), permittedCommentChars) + ")");
}

function writeComment(text) {
   writeln(formatComment(text));
}

function writeHeader(secID) {
   writeComment(description);
   cpsname = FileSystem.getFilename(getConfigurationPath());
   writeComment("Post-Processor : " + cpsname + " " + obversion);
   var unitstr = (unit == MM) ? 'mm' : 'inch';
   writeComment("Units = " + unitstr);

   writeln("");
   if (hasGlobalParameter("document-path")) {
      var path = getGlobalParameter("document-path");
      if (path) {
         writeComment("Drawing name : " + path);
      }
   }

   if (programName) {
      writeComment("Program Name : " + programName);
   }
   if (programComment) {
      writeComment("Program Comments : " + programComment);
   }
   writeln("");


   writeComment(numberOfSections + " Operation" + ((numberOfSections == 1) ? "" : "s") + " :");

   for (var i = secID; i < numberOfSections; ++i) {
      var section = getSection(i);
      var tool = section.getTool();
      isLaser = isPlasma = false;
      switch (tool.type) {
         case TOOL_LASER_CUTTER:
            isLaser = true;
            break;
         case TOOL_WATER_JET:
         case TOOL_PLASMA_CUTTER:
            isPlasma = true;
            break;
         default:
            isLaser = false;
            isPlasma = false;
      }

      if (section.hasParameter("operation-comment")) {
         writeComment((i + 1) + " : " + section.getParameter("operation-comment"));
         var op = section.getParameter("operation-comment")
      }
      else {
         writeComment(i + 1);
         var op = i + 1;
      }
      if (section.workOffset > 0) {
         writeComment("  Work Coordinate System : G" + (section.workOffset + 53));
      }
     
      kMinFeedrate(section, op);
      
      var machineTimeInSeconds = section.getCycleTime();
      var machineTimeHours = Math.floor(machineTimeInSeconds / 3600);
      machineTimeInSeconds = machineTimeInSeconds % 3600;
      var machineTimeMinutes = Math.floor(machineTimeInSeconds / 60);
      var machineTimeSeconds = Math.floor(machineTimeInSeconds % 60);
      var machineTimeText = "  Machining time : ";
      if (machineTimeHours > 0) {
         machineTimeText = machineTimeText + machineTimeHours + " hours " + machineTimeMinutes + " min ";
      }
      else
         if (machineTimeMinutes > 0) {
            machineTimeText = machineTimeText + machineTimeMinutes + " min ";
         }
      machineTimeText = machineTimeText + machineTimeSeconds + " sec";
      writeComment(machineTimeText);

     
   }
   
   allowHelicalMoves = false; 
   
   gAbsIncModal.reset();
   gFeedModeModal.reset();
   gPlaneModal.reset();
   writeBlock(gAbsIncModal.format(90), gFeedModeModal.format(94), gPlaneModal.format(17));
   switch (unit) {
      case IN:
         writeBlock(gUnitModal.format(20));
         break;
      case MM:
         writeBlock(gUnitModal.format(21));
         break;
   }

   writeln("");
   if (debugMode) {
      writeComment("debugMode is true");
      writeln("");
   }
}

function onOpen() {
   if (debugMode) writeComment("onOpen");
   // Number of checks capturing fatal errors
   // 2. is RadiusCompensation not set incorrectly ?
   onRadiusCompensation();

   // 3. moved to top of file
   myMachineConfig();

   // 4.  checking for duplicate tool numbers with the different geometry.
   // check for duplicate tool number
   numberOfSections = getNumberOfSections();
   writeHeader(0);
   gMotionModal.reset();

   zOutput.format(1);
}

function onComment(message) {
   writeComment(message);
}

function forceXYZ() {
   xOutput.reset();
   yOutput.reset();
   zOutput.reset();
}

function forceAny() {
   forceXYZ();
   feedOutput.reset();
   gMotionModal.reset();
}

function forceAll() {
   forceAny();
   sOutput.reset();
   gAbsIncModal.reset();
   gFeedModeModal.reset();
   gMotionModal.reset();
   gPlaneModal.reset();
   gUnitModal.reset();
   gWCSOutput.reset();
   mOutput.reset();
}

// go to initial position and optionally output the height check code before spindle turns on
function gotoInitial(checkit) {
   if (debugMode) writeComment("gotoInitial start");

   var sectionId = getCurrentSectionId();       // what is the number of this operation (starts from 0)
   var section = getSection(sectionId);         // what is the section-object for this operation
   var maxfeedrate = section.getMaximumFeedrate();

   // Rapid move to initial position, first XY, then Z, and do tool height check if needed
   forceAny();
   var initialPosition = getFramePosition(currentSection.getInitialPosition())
   f = feedOutput.format(maxfeedrate);
   writeBlock(gAbsIncModal.format(90), gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y), f);
   if (debugMode) writeComment("gotoInitial end");
}

// write a G53 Z retract
function writeZretract() {
   zOutput.reset();
   writeln("(This relies on homing, see https://openbuilds.com/search/127200199/?q=G53+fusion )");
   writeBlock(gFormat.format(53), gMotionModal.format(0), zOutput.format(toPreciseUnit(properties.machineHomeZ, MM)));  // Retract spindle to Machine Z Home
   gMotionModal.reset();
   zOutput.reset();
}


function onSection() {
   var nmbrOfSections = getNumberOfSections();  // how many operations are there in total
   var sectionId = getCurrentSectionId();       // what is the number of this operation (starts from 0)
   var section = getSection(sectionId);         // what is the section-object for this operation
   var tool = section.getTool();
   var maxfeedrate = section.getMaximumFeedrate();
   haveRapid = false; // drilling sections will have rapids even when other ops do not

   onRadiusCompensation(); // must check every section

   if (plasma_cutHeight <= 0)
      error("CUT HEIGHT MUST BE GREATER THAN 0");
   writeComment("Plasma pierce height " + plasma_pierceHeight);
   writeComment("Plasma pierce delay " + plasma_pierceDelay);
   writeComment("Plasma cut height " + plasma_cutHeight);

   // fake the radius else the arcs are too small before being linearized
   toolRadius = tool.diameter * 4;


   //TODO : plasma check that top height mode is from stock top and the value is positive
   //(onParameter =operation:plasma_cutHeight mode= from stock top)
   //(onParameter =operation:plasma_cutHeight value= 0.8)

   if (debugMode) writeComment("onSection " + sectionId);

   // Insert a small comment section to identify the related G-Code in a large multi-operations file
   var comment = "Operation " + (sectionId + 1) + " of " + nmbrOfSections;
   if (hasParameter("operation-comment")) {
      comment = comment + " : " + getParameter("operation-comment");
   }
   writeComment(comment);

   if (debugMode)
      writeComment("retractHeight = " + retractHeight);
   // Write the WCS, ie. G54 or higher.. default to WCS1 / G54 if no or invalid WCS
   if (!isFirstSection() && (currentworkOffset != (53 + section.workOffset))) {
      writeZretract();
   }
   if ((section.workOffset < 1) || (section.workOffset > 6)) {
      alert("Warning", "Invalid Work Coordinate System. Select WCS 1..6 in SETUP:PostProcess tab. Selecting default WCS1/G54");
      writeBlock(gWCSOutput.format(54));  // output what we want, G54
      currentworkOffset = 54;
   }
   else {
      writeBlock(gWCSOutput.format(53 + section.workOffset));  // use the selected WCS
      currentworkOffset = 53 + section.workOffset;
   }

   writeBlock(gAbsIncModal.format(90));  // Set to absolute coordinates

   forceXYZ();

   var remaining = currentSection.workPlane;
   if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      alert("Error", "Tool-Rotation detected - GRBL only supports 3 Axis");
      error("Fatal Error in Operation " + (sectionId + 1) + ": Tool-Rotation detected but GRBL only supports 3 Axis");
   }
   setRotation(remaining);

   forceAny();

}

function onDwell(seconds) {
   if (seconds > 0.0)
      writeBlock(gFormat.format(4), "P" + secFormat.format(seconds));
}

function onSpindleSpeed(spindleSpeed) {
   writeBlock(sOutput.format(spindleSpeed));
   gMotionModal.reset(); // force a G word after a spindle speed change to keep CONTROL happy
}

function onRadiusCompensation() {
   var radComp = getRadiusCompensation();
   var sectionId = getCurrentSectionId();
   if (radComp != RADIUS_COMPENSATION_OFF) {
      alert("Error", "RadiusCompensation is not supported in GRBL - Change RadiusCompensation in CAD/CAM software to Off/Center/Computer");
      error("Fatal Error in Operation " + (sectionId + 1) + ": RadiusCompensation is found in CAD file but is not supported in GRBL");
      return;
   }
}

function onRapid(_x, _y, _z) {
   if (debugMode) writeComment("onRapid");

   if (_z > Zmax) // store max z value for ending
      Zmax = _z;
   var x = xOutput.format(_x);
   var y = yOutput.format(_y);
   var z = "";
   // if (isPlasma && properties.UseZ)  // laser does not move Z during cuts
   // {
   //    z = zOutput.format(_z);
   // }
   if (isPlasma && properties.UseZ) { // && (xyzFormat.format(_z) == xyzFormat.format(plasma_cutHeight))) {
      if (debugMode) writeComment("onRapid skipping Z motion");
      if (x || y)
         writeBlock(gMotionModal.format(0), x, y);
      zOutput.reset();   // force it on next command
   }
   else
      if (x || y || z)
         writeBlock(gMotionModal.format(0), x, y, z);
   
}

function onLinear(_x, _y, _z, feed) {
   if (powerOn)   // do not reset if power is off - for laser G0 moves
   {
      xOutput.reset();
      yOutput.reset(); // always output x and y else arcs go mad
   }
   var x = xOutput.format(_x);
   var y = yOutput.format(_y);
   var f = feedOutput.format(feed);

   if (x || y) {
      var z = properties.UseZ ? zOutput.format(_z) : "";
      var s = sOutput.format(power);

      if (powerOn)
         writeBlock(gMotionModal.format(1), x, y, z, f, s);
      else
         writeBlock(gMotionModal.format(0), x, y, z, f, s);
      
   }
}


function onRapid5D(_x, _y, _z, _a, _b, _c) {
   alert("Error", "Tool-Rotation detected - GRBL only supports 3 Axis");
   error("Tool-Rotation detected but GRBL only supports 3 Axis");
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
   alert("Error", "Tool-Rotation detected - GRBL only supports 3 Axis");
   error("Tool-Rotation detected but GRBL only supports 3 Axis");
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
   var start = getCurrentPosition();
   xOutput.reset(); // always have X and Y, Z will output if it changed
   yOutput.reset();

   // arcs smaller than bitradius always have significant radius errors, so get radius and linearize them (because we cannot change minimumCircularRadius here)
   // note that larger arcs still have radius errors, but they are a much smaller percentage of the radius
   var rad = Math.sqrt(Math.pow(start.x - cx, 2) + Math.pow(start.y - cy, 2));
   if (properties.linearizeSmallArcs && (rad < toolRadius)) {
      if (debugMode) writeComment("linearizing arc radius " + round(rad, 4) + " toolRadius " + round(toolRadius, 3));
      linearize(tolerance);
      if (debugMode) writeComment("done");
      return;
   }
   if (isFullCircle()) {
      writeComment("full circle");
      linearize(tolerance);
      return;
   }
   else {
      if (!powerOn) {
         if (debugMode) writeComment("arc linearize rapid");
         linearize(tolerance * 4); // this is a rapid move so tolerance can be increased for faster motion and fewer lines of code
         if (debugMode) writeComment("arc linearize rapid done");
      }
      else
         switch (getCircularPlane()) {
            case PLANE_XY:
               zo = properties.UseZ ? zOutput.format(z) : "";
               writeBlock(gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zo, iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
               break;
            case PLANE_ZX:
               writeBlock(gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
               break;
            case PLANE_YZ:
               writeBlock(gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
               break;
            default:
               linearize(tolerance);
         }
   }
}

function onSectionEnd() {
   writeln("");
   forceAny();
}

function onClose() {

   writeBlock(gAbsIncModal.format(90));   // Set to absolute coordinates for the following moves
   writeBlock(mFormat.format(5));         // Stop Spindle

   gMotionModal.reset();
   xOutput.reset();
   yOutput.reset();
   if (properties.gotoMCSatend)    // go to MCS home
   {
      writeBlock(gAbsIncModal.format(90), gFormat.format(53),
         gMotionModal.format(0),
         zOutput.format(toPreciseUnit(properties.machineHomeZ, MM)));
      writeBlock(gAbsIncModal.format(90), gFormat.format(53),
         gMotionModal.format(0),
         xOutput.format(toPreciseUnit(properties.machineHomeX, MM)),
         yOutput.format(toPreciseUnit(properties.machineHomeY, MM)));
   }
   else
      writeBlock(gMotionModal.format(0), xOutput.format(0), yOutput.format(0));



   writeBlock(mFormat.format(30));  // Program End
}

function onCommand(command) {
   if (debugMode) writeComment("onCommand " + command);
   switch (command) {
      case COMMAND_STOP: // - Program stop (M00)
         writeComment("Program stop M00");
         writeBlock(mFormat.format(0));
         break;
      case COMMAND_OPTIONAL_STOP: // - Optional program stop (M01)
         writeComment("Optional program stop M01");
         writeBlock(mFormat.format(1));
         break;
      case COMMAND_END: // - Program end (M02)
         writeComment("Program end M02");
         writeBlock(mFormat.format(2));
         break;
      case COMMAND_POWER_OFF:
         if (debugMode) writeComment("power off");
         powerOn = false;
         writeBlock(mFormat.format(5));
         break;
      case COMMAND_POWER_ON:
         if (debugMode) writeComment("power ON");
         powerOn = true;
         writeBlock("G38.2", zOutput.format(toPreciseUnit(-properties.plasma_probeDistance, MM)), feedOutput.format(toPreciseUnit(properties.plasma_probeRate, MM)));
         if (debugMode) writeComment("touch offset " + xyzFormat.format(properties.plasma_touchoffOffset));
         writeBlock(gMotionModal.format(10), "L20", zOutput.format(toPreciseUnit(-properties.plasma_touchoffOffset, MM)));
         feedOutput.reset();
         writeBlock(gMotionModal.format(0), zOutput.format(plasma_pierceHeight));
         writeBlock(mFormat.format(3), sOutput.format(power), clnt);
         onDwell(plasma_pierceDelay);
         writeBlock(gMotionModal.format(0), zOutput.format(plasma_cutHeight));
         probed = true;
         break;
      default:
         if (debugMode) writeComment("onCommand not handled " + command);
   }
   // for other commands see https://cam.autodesk.com/posts/reference/classPostProcessor.html#af3a71236d7fe350fd33bdc14b0c7a4c6
   if (debugMode) writeComment("onCommand end");
}

function onParameter(name, value) {
   if (debugMode) writeComment("onParameter =" + name + "= " + value);   // (onParameter =operation:retractHeight value= :5)
   name = name.replace(" ", "_"); // dratted indexOF cannot have spaces in it!
   if ((name.indexOf("retractHeight_value") >= 0))   // == "operation:retractHeight value")
   {
      retractHeight = value;
      if (debugMode) writeComment("retractHeight = " + retractHeight);
   }
   if (name.indexOf("operation:clearanceHeight_value") >= 0) {
      clearanceHeight = value;
      if (debugMode) writeComment("clearanceHeight = " + clearanceHeight);
   }

   if (name.indexOf("movement:lead_in") !== -1) {
      leadinRate = value;
      if (debugMode && isPlasma) writeComment("leadinRate set " + leadinRate);
   }

   if (name.indexOf('operation:cuttingMode') >= 0) {
      cuttingMode = value;
      if (debugMode) writeComment("cuttingMode set " + cuttingMode);
      if (cuttingMode.indexOf('cut') >= 0) // simplify later logic, auto/low/medium/high are all 'cut'
         cuttingMode = 'cut';
      if (cuttingMode.indexOf('auto') >= 0)
         cuttingMode = 'cut';
   }
   if (name == 'operation:tool_pierceHeight') {
      if (properties.plasma_pierceHeightoverride)
         plasma_pierceHeight = properties.plasma_pierceHeightValue;
      else
         plasma_pierceHeight = value;
   }
   if (name == 'operation:tool_pierceTime') {
      if (properties.plasma_pierceDelayOverride)
         plasma_pierceDelay = properties.plasma_pierceDelay;
      else
         plasma_pierceDelay = value;
   }
   if (name == 'operation:tool_cutHeight') {
      if (properties.plasma_cutHeightoverride)
         plasma_cutHeight = properties.plasma_cutHeightValue;
      else
         plasma_cutHeight = value;
   }
}

function round(num, digits) {
   return toFixedNumber(num, digits, 10)
}

function toFixedNumber(num, digits, base) {
   var pow = Math.pow(base || 10, digits); // cleverness found on web
   return Math.round(num * pow) / pow;
}
