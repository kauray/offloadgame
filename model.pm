 
smg

player scheduler
	[deviceex], [serverex], [retaindevice], [retainserver], [migtoserver], [migtodevice], [migdonedev], [notaskmig], [devicerunningcost], [core1], [core2], [migonetwo], [migtwoone], [retaincore1], [retaincore2]
endplayer


player environment
//    transmitter, battery, server, [devtranmission]
//    transmitter, [totransmit], [devtranmission], [serverexecution]
    [updatebatteryoffload]
endplayer

const int pmax = 5;
const int latencym = 100;
const int tmax = 50;
const int slottime = 20;

const double e = 2.718281828459045;
const double ib = pcpu / 0.6;
const double b21 = -0.043;
const double b22 = -14.275;
const double vsoc = 0.96; // vsoc = cb / cfull * 1 V
const double b23 = 0.154;
//const double voc;
const double kd = 0.019;

const double b11 = -0.265;
const double b12 = -61.649;
const double b13 = -2.039;
const double b14 = 5.276;
const double b15 = -4.173;
const double b16 = 1.654;
const double b17 = 3.356;


// constants for p_device
const double ccf = 0.00642;
const double xcf = 1500;
const double xck = 0.01;
const double xcu = 0.05;
const double p0xcpu = 0.332;

const double p11;
const double p12;
const double p13;
const double p14;
const double p15;
const double p21;
const double p22;
const double p23;
const double p24;
const double p25;
const double p31;
const double p32;
const double p33;
const double p34;
const double p35;

global turn : [0..3] init 0;

//formula energyconsumed = floor(packetstransmitted + harvestedpackets);

//formula one = floor(level + cputil);

formula etdtlittle = batteryenergy - econsumedlittle;
formula etdtbig = batteryenergy - econsumedbig;
formula etdtserver = batteryenergy - econsumedserver;

formula econsumedlittle = slottime  * pcpulittle * e_loss;
formula econsumedbig = slottime  * pcpubig * e_loss;
formula econsumedserver = slottime  * pcpuserver * e_loss;


//full power
//formula p_device = pcpu + p3g + wifi; //p_device will be calculated in the module

//cpu power
formula p_device = pcpu; //p_device will be calculated in the module

formula pcpulittle = 1;
formula pcpubig = 5;
formula pcpuserver = 20;

formula pcpu = ccf * xcf * (xck    + xcu) + p0xcpu;
//formula p3g = x3gon * ((c3gi * x3gi)  + (c3gf * x3gf)  + (c3gd * x3gd));
//formula wifi = xwon * ((cwflow * xwflow) + (cwfhigh * xwfhigh));


formula e_loss = slottime  * (ib * ib * b21* pow(e, ((b22*vsoc) + b23))) + (ib * voc * (pow(ib, kd) - 1));

formula voc = b11 * pow(e, (b12 * vsoc)) + 
        b13 * pow(vsoc, 4) + 
        b14 * pow(vsoc, 3) + 
        b15 * pow(vsoc, 2) + 
        b16 * vsoc + 
        b17  
        ; 

//model of temperature

const double tenv;
const double rcpuenv = 35.8;
const double rbatenv = 7.58;
const double rcpubat = 78.8; //to be calculated
const double pbatlittle = 6.67;
const double pbatbig = 33.33;

formula tempbatterylittle = tenv + (rcpuenv * rbatenv) / (rbatenv + rcpubat + rcpuenv) * pcpulittle ;
// + 
//((rcpuenv * rbatenv) + (rcpubat*rbatenv)) / (rbatenv + rcpubat + rcpuenv) * pbatlittle;

formula tempbatterybig = tenv + (rcpuenv * rbatenv) / (rbatenv + rcpubat + rcpuenv) * pcpubig  ;
//+ 
//((rcpuenv * rbatenv) + (rcpubat*rbatenv)) / (rbatenv + rcpubat + rcpuenv) * pbatbig;


//migration lock parameter
const int k = 3;

module offloadchoice
    execution : [-1..1] init -1; // -1 initial, 0 execution on device, 1 execution offload
    tmig : [0..2] init 0; //task migration status -- 0 retain 1 migrate from device to server, 2 migrate from server to device

    //non-deterministic choice of on device computation versus offload to edge server
    [deviceex] turn = 0 & execution = -1 -> (execution' = 0) & (turn' = 1);
    [serverex] turn = 0 & execution = -1 -> (execution' = 1) & (turn' = 1);

    //non-deterministic choice of migrate across server

    //when executing on device
    [retaindevice] turn = 0 & mod(dtime,k) = 0 & execution = 0 & tmig = 0 & temp1 < 30 & temp2 < 30 -> (tmig' = 0) & (execution' = 0) & (turn' = 1); // retain
    [migtoserver] turn = 0 & mod(dtime,k) = 0 & execution = 0 & tmig = 0 -> (tmig' = 1) & (execution' = 1) & (turn' = 0); // migrate

    //when executing on server
    [retainserver] turn = 0 &  mod(dtime,k) = 0 & execution = 1 & tmig = 0 -> (tmig' = 0) & (execution' = 1) & (turn' = 1); // retain
    [migtodevice] turn = 0 & mod(dtime,k) = 0 & execution = 1 & tmig = 0 -> (tmig' = 2) & (execution' = 0) & (turn' = 0); // migrate

    //remaining cases

    [migdone] turn = 0 & (tmig = 1 | tmig = 2) & mod(dtime, k) = 0 -> (tmig' = 0) & (turn' = 1); // state is used for migration cost with rewards definition
    [notaskmig] turn = 0 & execution != -1 & mod(dtime,k) != 0 -> (turn' = 1) ;

    //[updatebatteryoffload] turn = 1 & (execution = 0 | execution = 1)  -> (tmig' = 0);

    //[updatebatteryoffload] turn = 1 & (execution = 0 | execution = 1) & dtime < tmax  -> (tmig' = 0);
    [] turn = 0 & dtime = tmax -> true;
endmodule

module device
    batteryenergy : [0..28800] init 28800;
    //device battery

    temp1 : [10..90] init ceil(tenv);
    temp2 : [10..90] init ceil(tenv);
    //battery temperature

    mig : [0..2] init 0;
    core : [0..2] init 0;

    dtime : [0..tmax] init 0;
    //little core, big core non determinism

    //cputil : [0..100] init 0;
    //execution : [-1..1] init -1;
    
    //receivedata : bool init false;
    //packetstransmitted : [0..pmax] init 0;

    //non deterministically select the core
    [core1] turn = 1 & execution = 0 & dtime < tmax & core = 0 -> (core' = 1) & (turn' = 2);
    [core2] turn = 1 & execution = 0 & dtime < tmax & core = 0 -> (core' = 2) & (turn' = 2);


    //non deterministically select core migration
    [retaincore1] turn = 1 & mod(dtime,k) = 0 & dtime < tmax & core = 1 & execution = 0   -> (core' = 1) & (mig' = 0) & (turn' = 2); // retain
    [migonetwo] turn = 1 & mod(dtime,k) = 0 & dtime < tmax & core = 1 & execution = 0 -> (core' = 2) & (mig' = 1) & (turn' = 2); // migrate
    [migtwoone] turn = 1 & mod(dtime,k) = 0 & dtime < tmax & core = 2 & execution = 0 -> (core' = 1) & (mig' = 2) & (turn' = 2); // migrate
    [retaincore2] turn = 1 & mod(dtime,k) = 0 & dtime < tmax & core = 2 & execution = 0  -> (core' = 2) & (mig' = 0) & (turn' = 2); // retain

    //[migdonedev] turn = 1 & (mig = 1 | mig = 2) & mod(dtime, k) = 0 -> (mig' = 0) & (turn' = 2); // state is used for migration cost with rewards definition
    [migdonedev] turn = 1 & mod(dtime,k) != 0 & dtime < tmax & core != 0 & execution = 0 -> (mig' = 0) & (turn' = 2); // retain

    //non deterministically select core migration with previous core
    //[devicerunning] turn = 1 & mod(dtime,k) = 0 & dtime < tmax -> (pcore' = core) & (core' = 1) & (turn' = 1);
    //[devicerunning] turn = 1 & mod(dtime,k) = 0 & dtime < tmax -> (pcore' = core) & (core' = 2) & (turn' = 1);

    //if running on device, calculate power consumption according to core
    //take into consideration migration across cores
    [devicerunningcost] turn = 2 & execution = 0 & dtime < tmax & batteryenergy > 0 & core = 1 -> 
  (batteryenergy' = floor(etdtlittle)) & (temp1' = ceil(tempbatterylittle))  & (dtime' = dtime + 1) & (mig' = 0) & (turn' = 0);
    [devicerunningcost] turn = 2 & execution = 0 & dtime < tmax & batteryenergy > 0 & core = 2  -> 
  (batteryenergy' = floor(etdtbig)) & (temp2' = ceil(tempbatterybig)) & (dtime' = dtime + 1) & (mig' = 0) & (turn' = 0);
    //[devicerunningcost] turn = 2 & execution = 0 & dtime < tmax & batteryenergy > 0 & mig = 2  -> 
  //(batteryenergy' = floor(etdt)) & (dtime' = dtime + 1) & (mig' = 0) & (turn' = 0);


    //if offloaded, determine the power consumption in terms of offload
    //[offload] turn = 0 & execution = 1 & dtime < tmax -> 0.4 : (receivedata' = true) & (turn' = 1) + 0.6 : (receivedata' = false) & (turn' = 1);
    //[devtranmission1] turn = 1 & receivedata & execution = 1 & dtime < tmax -> 0.6 : (packetstransmitted' = 0) & (turn' = 2) + 0.2 : (packetstransmitted' = 1) & (turn' = 2) + 0.2 : (packetstransmitted' = 2) & (turn' = 2) ;
    //[devtranmission2] turn = 1 & !receivedata & execution = 1 & dtime < tmax -> (packetstransmitted' = 0) & (turn' = 2) ;

    [updatebatteryoffload] turn = 1 & execution = 1 & batteryenergy > 0 & dtime < tmax -> 
	(batteryenergy' = floor(etdtserver)) & (temp1' = ceil(tenv)) & (temp2' = ceil(tenv)) & (turn' = 0) & (dtime' = dtime + 1);

    //[updatebatteryoffload2] turn = 1 & execution = 1 & batteryenergy > 0 & dtime < tmax -> 
	//	(batteryenergy' = etdt) & (turn' = 3);
    [] dtime = tmax -> (dtime' = tmax);
endmodule

module server
    latency : [0..latencym] init 0;
    
    //this module will be filled in from the naive bayes learning
    [updatebatteryoffload] turn = 1 & execution = 1 & dtime < tmax ->
	 p11 : (latency' = 0) + p12 : (latency' = 1) + p13 : (latency' = 2) + p14 : (latency' = 3) + p15 : (latency' = 4);

    [devicerunningcost] turn = 2 & execution = 0 & dtime < tmax & batteryenergy > 0 & core = 1 ->
	 p21 : (latency' = 0) + p22 : (latency' = 1) + p23 : (latency' = 2) + p24 : (latency' = 3) + p25 : (latency' = 4);

    [devicerunningcost] turn = 2 & execution = 0 & dtime < tmax & batteryenergy > 0 & core = 2 ->
	 p31 : (latency' = 0) + p32 : (latency' = 1) + p33 : (latency' = 2) + p34 : (latency' = 3) + p35 : (latency' = 4);
endmodule

//module timer
//    [dtmax] dtime = tmax & turn = 4 -> (dtime' = dtime);
//    [devicerunning] dtime < tmax & turn = 4 -> (dtime' = dtime + 1);
//    [serverexecution] dtime < tmax & turn = 4 -> (dtime' = dtime + 1);
//endmodule

rewards "latency"
    latency = 0 : 500;
    latency = 1 : 400;
    latency = 2 : 300;
    latency = 3 : 200;
    latency = 4 : 100;
endrewards

rewards "nopref"
    true : 1;
endrewards

rewards "energy"
    true : batteryenergy;
endrewards

rewards "server"
    execution = 1 : 500;
endrewards

rewards "jointlatencyenergy"
    latency = 0 : 100;
    latency = 1 : 100;
    latency = 2 : 100;
    latency = 3 : 50;
    latency = 4 : 50;
    true : batteryenergy;
endrewards

rewards "eqlatency"
    latency = 0 : latency + batteryenergy;
    latency = 1 : latency + batteryenergy;
    latency = 2 : latency + batteryenergy;
    latency = 3 : latency + batteryenergy;
    latency = 4 : latency + batteryenergy;
    tmig = 1 | tmig = 2 : -1;
    mig = 1 | mig = 2 : -1;
//    latency = 0 & mig != 0 & tmig != 0: 0;
//    latency = 1 & mig != 0 & tmig != 0: 0;
//    latency = 2 & mig != 0 & tmig != 0: 0;
//    latency = 3 & mig != 0 & tmig != 0: 0;
//    latency = 4 & mig != 0 & tmig != 0: 0;
endrewards
