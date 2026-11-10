MODULE PalletProgram

    !***********************************************************************
    ! Industrial Robotics and Offline Programming G1F - University of Skovde
    ! Offline programming project: Pallet Project - Group 2 (JMPM)
    ! Authors: Peru Mendivil and Joaquin Moreno
    ! Robot :   ABB IRB 1600-10/1.45, IRC5 RobotWare 6.13.02 (RobotStudio 2025)
    ! Tool  :   toolVacuum, vacuum gripper with 6 cups (one valve per cup)
    ! Date:    2026-11-09
    !
    ! The robot palletizes two products coming on two conveyors.
    ! Box 1 goes from conveyor 1 to the Euro pallet: 4-2 pattern,
    ! 2 layers (12 boxes). Box 2 goes from conveyor 2 to the stacking
    ! table, where a 3x2 block is formed. The block is then moved to the
    ! half pallet: 2x2 blocks per layer, 3 layers (72 boxes), with a liner
    ! after layers 1 and 2. When both conveyors have a box, the robot
    ! alternates box 1 and box 2. A full pallet is replaced by the operator
    ! from outside the fence, and the robot keeps working with the other
    ! product. With the half pallet full, one block can still be finished
    ! on the table, and it waits there. If the liner stack is empty, the
    ! robot keeps working until a liner is needed; then box 2 waits until
    ! the operator refills the stack.
    !
    ! Structure: Main is a state machine (grafcet). It initialises the
    ! signals and then decides each cycle which box to handle, from the
    ! conveyor sensors, the full-pallet flags and the last box handled.
    ! Each product has its own routine with a finite-state machine for
    ! the place positions. Every place position is calculated with Offs
    ! from one base target per station. ApproachPoint does every
    ! pick/place: approach, vacuum on/off and GripLoad. In a pick, the
    ! robot waits until the analog signal AI_VacuumPressure reaches the
    ! pressure needed for that load (GripWithVacuum). Work objects,
    ! tool and loads are in the module CalibData.
    ! The operator buttons (pallet replaced, liners refilled) are read
    ! with interrupts (TRAP), so a short press is never lost.
    !
    ! Naming: VAR, PERS and parameters in camelCase (can change);
    ! CONST, PROC, FUNC and MODULE in PascalCase (fixed).
    !***********************************************************************

    !-----------------------------------------------------------------------
    ! Base targets
    !-----------------------------------------------------------------------
    CONST jointtarget Home:=[[0,0,0,0,90,0],[9E+09,9E+09,9E+09,9E+09,9E+09,9E+09]];

    ! Box 1
    CONST robtarget PickConveyor1:=[[249.5,0,200],[0,0,1,0],[0,0,0,0],[9E+09,9E+09,9E+09,9E+09,9E+09,9E+09]];
    CONST robtarget PlaceEuroRow4:=[[225,525,200],[0,-0.707106781,0.707106781,0],[-2,0,0,0],[9E+09,9E+09,9E+09,9E+09,9E+09,9E+09]];
    CONST robtarget PlaceEuroRow2:=[[350,150,200],[0,1,0,0],[-2,0,-1,0],[9E+09,9E+09,9E+09,9E+09,9E+09,9E+09]];

    ! Box 2
    CONST robtarget PickConveyor2:=[[-35.5,-160,200],[0,-0.707106781,0.707106781,0],[0,0,0,0],[9E+09,9E+09,9E+09,9E+09,9E+09,9E+09]];
    CONST robtarget PlaceTable:=[[-95,165,200],[0,0,1,0],[0,0,0,0],[9E+09,9E+09,9E+09,9E+09,9E+09,9E+09]];
    CONST robtarget PickTableStack:=[[195,130,200],[0,0,1,0],[0,0,0,0],[9E+09,9E+09,9E+09,9E+09,9E+09,9E+09]];
    CONST robtarget PlaceHalfPallet:=[[205,170,200],[0,0,1,0],[0,0,0,0],[9E+09,9E+09,9E+09,9E+09,9E+09,9E+09]];

    ! Liners
    CONST robtarget PickLiner:=[[400,270,100],[0,0,1,0],[0,0,0,0],[9E+09,9E+09,9E+09,9E+09,9E+09,9E+09]];
    CONST robtarget PlaceLiner:=[[400,300,210],[0,0,1,0],[0,0,0,0],[9E+09,9E+09,9E+09,9E+09,9E+09,9E+09]];

    !-----------------------------------------------------------------------
    ! Speeds and heights
    !-----------------------------------------------------------------------
    CONST speeddata TransitSpeed:=v1000;
    CONST speeddata ApproachSpeed:=v300;
    CONST speeddata HomeSpeed:=v100;
    ! Zone of the retract move after a pick or a place
    CONST zonedata PickRetractZone:=z10;    ! next move (transit) is known: blend
    CONST zonedata PlaceRetractZone:=fine;  ! next move depends on Main: stop

    ! Height of every station (world)
    CONST num ConveyorsHeight:=768;
    CONST num TableHeight:=770;
    CONST num LinerStandHeight:=500;
    CONST num EuroPalletHeight:=144;
    CONST num HalfPalletHeight:=144;

    CONST num Box1Height:=200;
    CONST num Box2Height:=200;

    ! Heights for the approach points
    CONST num TransitHeight:=1100;
    CONST num PalletOffsetHeight:=250;
    CONST num MinApproachHeight:=250;

    ! Station identifiers for ApproachHeight
    CONST num StationConveyor1:=1;
    CONST num StationConveyor2:=2;
    CONST num StationTable:=3;
    CONST num StationLinerStand:=4;
    CONST num StationHalfPallet:=5;
    CONST num StationEuroPallet:=6;

    !-----------------------------------------------------------------------
    ! Vacuum gripper
    !-----------------------------------------------------------------------
    ! Vacuum pressure needed to lift each load (bar), read from AI_VacuumPressure
    CONST num PressureBox1:=4;
    CONST num PressureBox2:=2;
    ! Block of 6 boxes 2: one box per cup, same pressure as one box 2 (assumption)
    CONST num PressureStack:=2;
    ! Liner: light load shared by the 6 cups (assumption)
    CONST num PressureLiner:=2;
    ! Maximum time to reach the pressure before reporting an error (s)
    CONST num VacuumMaxTime:=2;
    ! Time to let the vacuum out after closing the valves (s)
    CONST num ReleaseTime:=1;
    CONST bool CupsAllOn{6}:=[TRUE,TRUE,TRUE,TRUE,TRUE,TRUE];
    CONST bool CupsAllOff{6}:=[FALSE,FALSE,FALSE,FALSE,FALSE,FALSE];
    CONST bool CupsBox2On{6}:=[FALSE,FALSE,FALSE,TRUE,FALSE,FALSE];
    VAR signaldo cupSignals{6};

    !-----------------------------------------------------------------------
    ! Box selection
    !-----------------------------------------------------------------------
    CONST num Box1:=1;
    CONST num Box2:=2;
    ! Last box handled, to alternate box 1 and box 2
    VAR num lastBox:=Box2;

    !-----------------------------------------------------------------------
    ! Box 1 state machine parameters and variables
    !-----------------------------------------------------------------------
    CONST num Box1Pos1:=1;
    CONST num Box1Pos2:=2;
    CONST num Box1Pos3:=3;
    CONST num Box1Pos4:=4;
    CONST num Box1Pos5:=5;
    CONST num Box1LastPos:=6;
    CONST num Box1MaxLayers:=2;
    ! Distance between boxes in the row of 4 and in the row of 2
    CONST num EuroRow4Offset:=250;
    CONST num EuroRow2Offset:=500;

    VAR num box1State:=1;
    VAR num box1Layer:=1;
    VAR bool euroPalletFull:=FALSE;

    ! Euro pallet replaced by the operator: interrupt and flag set by the TRAP
    VAR intnum euroReplacedInt;
    VAR bool euroPalletReplaced:=FALSE;

    !-----------------------------------------------------------------------
    ! Box 2 state machine parameters and variables (table)
    !-----------------------------------------------------------------------
    CONST num Box2Pos1:=1;
    CONST num Box2Pos2:=2;
    CONST num Box2Pos3:=3;
    CONST num Box2Pos4:=4;
    CONST num Box2Pos5:=5;
    CONST num Box2LastPos:=6;
    ! Distance between boxes 2 on the table
    CONST num Box2Offset:=130;

    VAR num box2State:=1;
    VAR bool tableFull:=FALSE;

    !-----------------------------------------------------------------------
    ! TransferStack parameters and variables (half pallet)
    !-----------------------------------------------------------------------
    CONST num BlockPos1:=1;
    CONST num BlockPos2:=2;
    CONST num BlockPos3:=3;
    CONST num BlockPos4:=4;
    CONST num Box2MaxLayers:=3;
    ! Distance between 3x2 blocks on the half pallet
    CONST num BlockOffsetX:=3*Box2Offset;
    CONST num BlockOffsetY:=2*Box2Offset;

    VAR num blockState:=1;
    VAR num box2Layer:=1;
    VAR bool halfPalletFull:=FALSE;

    ! Half pallet replaced by the operator: interrupt and flag set by the TRAP
    VAR intnum halfReplacedInt;
    VAR bool halfPalletReplaced:=FALSE;

    !-----------------------------------------------------------------------
    ! Liners parameters and variables
    !-----------------------------------------------------------------------
    CONST num TotalLiners:=10;
    CONST num LinerHeight:=10;

    VAR num linersLeft:=TotalLiners;
    ! Liner stack empty: warning to the operator, the robot keeps working
    VAR bool linerStackEmpty:=FALSE;
    ! Layer complete but the liner stack is empty: box 2 waits for the refill
    VAR bool linerMissing:=FALSE;

    ! Liners refilled by the operator: interrupt and flag set by the TRAP
    VAR intnum linersRefilledInt;
    VAR bool linersRefilled:=FALSE;

    !-----------------------------------------------------------------------
    ! Main: choose the box and check the operator signals
    !-----------------------------------------------------------------------
    PROC Main()

        InitSignals;
        VacuumControl CupsAllOff;
        SetDO DO_EuroPalletFull,0;
        SetDO DO_HalfPalletFull,0;
        SetDO DO_LinerStackEmpty,0;
        ! Connect an interrupt to DI_EuroPalletReplaced: EuroPalletReplacedTrap runs on every rising edge
        IDelete euroReplacedInt;
        CONNECT euroReplacedInt WITH EuroPalletReplacedTrap;
        ISignalDI DI_EuroPalletReplaced,1,euroReplacedInt;
        ! Connect an interrupt to DI_HalfPalletReplaced: HalfPalletReplacedTrap runs on every rising edge
        IDelete halfReplacedInt;
        CONNECT halfReplacedInt WITH HalfPalletReplacedTrap;
        ISignalDI DI_HalfPalletReplaced,1,halfReplacedInt;
        ! Connect an interrupt to DI_LinersRefilled: LinersRefilledTrap runs on every rising edge
        IDelete linersRefilledInt;
        CONNECT linersRefilledInt WITH LinersRefilledTrap;
        ISignalDI DI_LinersRefilled,1,linersRefilledInt;
        GripLoad load0;
        MoveAbsJ Home,HomeSpeed,fine,toolVacuum;

        WHILE TRUE DO

            ! Alternate box 1 and box 2 when both are ready
            IF Box1Ready() AND ((NOT Box2Ready()) OR lastBox=Box2) THEN
                ProcessBox1;
            ELSEIF Box2Ready() THEN
                ProcessBox2;
            ENDIF

            ! Euro pallet replaced (flag set by the TRAP): back to layer 1
            IF euroPalletReplaced THEN
                euroPalletReplaced:=FALSE;
                box1Layer:=1;
                ! Not necessary but safe
                box1State:=Box1Pos1;
                euroPalletFull:=FALSE;
            ENDIF

            ! Half pallet replaced (flag set by the TRAP): layer 1 first, then the waiting block
            IF halfPalletReplaced THEN
                halfPalletReplaced:=FALSE;
                box2Layer:=1;
                blockState:=BlockPos1;
                halfPalletFull:=FALSE;
                IF tableFull THEN
                    TransferStack;
                    tableFull:=FALSE;
                ENDIF
            ENDIF

            ! Liners refilled (flag set by the TRAP): reload the counter, then the missing liner and the waiting block
            IF linersRefilled THEN
                linersRefilled:=FALSE;
                linersLeft:=TotalLiners;
                linerStackEmpty:=FALSE;
                IF linerMissing THEN
                    linerMissing:=FALSE;
                    PlaceLayerLiner;
                    IF tableFull THEN
                        TransferStack;
                        tableFull:=FALSE;
                    ENDIF
                ENDIF
            ENDIF
            WaitTime 0.1;
        ENDWHILE
    ENDPROC

    !-----------------------------------------------------------------------
    ! Interrupts: operator buttons (pallet replaced, liners refilled)
    !-----------------------------------------------------------------------
    TRAP EuroPalletReplacedTrap
        ! Only considered if the pallet is already full to prevent false positives
        IF euroPalletFull THEN
            ! Light off at once, even while the robot moves: the operator instantly sees the press was accepted
            SetDO DO_EuroPalletFull,0;
            ! Main sets layer 1 when the robot is free (no motion in a TRAP)
            euroPalletReplaced:=TRUE;
        ENDIF
    ENDTRAP

    TRAP HalfPalletReplacedTrap
        ! Only considered if the pallet is already full to prevent false positives
        IF halfPalletFull THEN
            ! Light off at once, even while the robot moves: the operator instantly sees the press was accepted
            SetDO DO_HalfPalletFull,0;
            ! Main sets layer 1 and moves the waiting block (no motion in a TRAP)
            halfPalletReplaced:=TRUE;
        ENDIF
    ENDTRAP

    TRAP LinersRefilledTrap
        ! Only if the stack is empty, to prevent false positives
        IF linerStackEmpty THEN
            ! Light off at once, even while the robot moves: the operator instantly sees the press was accepted
            SetDO DO_LinerStackEmpty,0;
            ! Main reloads the counter, then places the missing liner and block (no motion in a TRAP)
            linersRefilled:=TRUE;
        ENDIF
    ENDTRAP

    !-----------------------------------------------------------------------
    ! Box ready to be handled
    !-----------------------------------------------------------------------
    FUNC bool Box1Ready()
        ! Box 1 waiting on conveyor 1 and room on the Euro pallet
        RETURN (DI_Box1Arrived=1) AND (NOT euroPalletFull);
    ENDFUNC

    FUNC bool Box2Ready()
        ! Box 2 waiting on conveyor 2 and room on the table
        RETURN (DI_Box2Arrived=1) AND (NOT tableFull);
    ENDFUNC

    !-----------------------------------------------------------------------
    ! Box 1 state machine: conveyor 1 to the Euro pallet
    !-----------------------------------------------------------------------
    PROC ProcessBox1()
        ! Z of the current layer on the Euro pallet
        VAR num layerZ;

        ApproachPoint PickConveyor1,wobjConveyor1,CupsAllOn,loadBox1,ApproachHeight(StationConveyor1),PickRetractZone\pressure:=PressureBox1;

        layerZ:=(box1Layer-1)*Box1Height;
        TEST box1State
        CASE Box1Pos1:
            ApproachPoint Offs(PlaceEuroRow4,0,0,layerZ),wobjEuroPallet,CupsAllOff,load0,ApproachHeight(StationEuroPallet),PlaceRetractZone;
            box1State:=Box1Pos2;
        CASE Box1Pos2:
            ApproachPoint Offs(PlaceEuroRow4,EuroRow4Offset,0,layerZ),wobjEuroPallet,CupsAllOff,load0,ApproachHeight(StationEuroPallet),PlaceRetractZone;
            box1State:=Box1Pos3;
        CASE Box1Pos3:
            ApproachPoint Offs(PlaceEuroRow4,2*EuroRow4Offset,0,layerZ),wobjEuroPallet,CupsAllOff,load0,ApproachHeight(StationEuroPallet),PlaceRetractZone;
            box1State:=Box1Pos4;
        CASE Box1Pos4:
            ApproachPoint Offs(PlaceEuroRow4,3*EuroRow4Offset,0,layerZ),wobjEuroPallet,CupsAllOff,load0,ApproachHeight(StationEuroPallet),PlaceRetractZone;
            box1State:=Box1Pos5;
        CASE Box1Pos5:
            ApproachPoint Offs(PlaceEuroRow2,0,0,layerZ),wobjEuroPallet,CupsAllOff,load0,ApproachHeight(StationEuroPallet),PlaceRetractZone;
            box1State:=Box1LastPos;
        CASE Box1LastPos:
            ApproachPoint Offs(PlaceEuroRow2,EuroRow2Offset,0,layerZ),wobjEuroPallet,CupsAllOff,load0,ApproachHeight(StationEuroPallet),PlaceRetractZone;
            IF box1Layer=Box1MaxLayers THEN
                euroPalletFull:=TRUE;
                SetDO DO_EuroPalletFull,1;
                TPWrite "Euro pallet full: replace it, then press the Euro pallet replaced button";
            ELSE
                Incr box1Layer;
            ENDIF
            box1State:=Box1Pos1;
        DEFAULT:
            box1State:=Box1Pos1;
        ENDTEST
        lastBox:=Box1;
    ENDPROC

    !-----------------------------------------------------------------------
    ! Box 2 state machine: conveyor 2 to the table
    !-----------------------------------------------------------------------
    PROC ProcessBox2()

        ApproachPoint PickConveyor2,wobjConveyor2,CupsBox2On,loadBox2,ApproachHeight(StationConveyor2),PickRetractZone\pressure:=PressureBox2;

        ! Far row (y=130) first and x from high to low: the box carried never crosses the boxes already placed
        TEST box2State
        CASE Box2Pos1:
            ApproachPoint Offs(PlaceTable,2*Box2Offset,Box2Offset,0),wobjTable,CupsAllOff,load0,ApproachHeight(StationTable),PlaceRetractZone;
            box2State:=Box2Pos2;
        CASE Box2Pos2:
            ApproachPoint Offs(PlaceTable,Box2Offset,Box2Offset,0),wobjTable,CupsAllOff,load0,ApproachHeight(StationTable),PlaceRetractZone;
            box2State:=Box2Pos3;
        CASE Box2Pos3:
            ApproachPoint Offs(PlaceTable,0,Box2Offset,0),wobjTable,CupsAllOff,load0,ApproachHeight(StationTable),PlaceRetractZone;
            box2State:=Box2Pos4;
        CASE Box2Pos4:
            ApproachPoint Offs(PlaceTable,2*Box2Offset,0,0),wobjTable,CupsAllOff,load0,ApproachHeight(StationTable),PlaceRetractZone;
            box2State:=Box2Pos5;
        CASE Box2Pos5:
            ApproachPoint Offs(PlaceTable,Box2Offset,0,0),wobjTable,CupsAllOff,load0,ApproachHeight(StationTable),PlaceRetractZone;
            box2State:=Box2LastPos;
        CASE Box2LastPos:
            ApproachPoint Offs(PlaceTable,0,0,0),wobjTable,CupsAllOff,load0,ApproachHeight(StationTable),PlaceRetractZone;
            IF halfPalletFull OR linerMissing THEN
                tableFull:=TRUE;
            ELSE
                TransferStack;
            ENDIF
            box2State:=Box2Pos1;
        DEFAULT:
            box2State:=Box2Pos1;
        ENDTEST
        lastBox:=Box2;
    ENDPROC

    !-----------------------------------------------------------------------
    ! Box 2: move the 3x2 block from the table to the half pallet
    !-----------------------------------------------------------------------
    PROC TransferStack()
        ! Z of the current layer on the half pallet (block and liner)
        VAR num layerZ;

        ! Pick all 6 boxes 2
        ApproachPoint PickTableStack,wobjTable,CupsAllOn,loadBox2Stack,ApproachHeight(StationTable),PickRetractZone\pressure:=PressureStack;

        ! Place group of boxes
        layerZ:=HalfPalletLayerZ();
        TEST blockState
        CASE BlockPos1:
            ApproachPoint Offs(PlaceHalfPallet,0,BlockOffsetY,layerZ),wobjHalfPallet,CupsAllOff,load0,ApproachHeight(StationHalfPallet),PlaceRetractZone;
            blockState:=BlockPos2;
        CASE BlockPos2:
            ApproachPoint Offs(PlaceHalfPallet,BlockOffsetX,BlockOffsetY,layerZ),wobjHalfPallet,CupsAllOff,load0,ApproachHeight(StationHalfPallet),PlaceRetractZone;
            blockState:=BlockPos3;
        CASE BlockPos3:
            ApproachPoint Offs(PlaceHalfPallet,0,0,layerZ),wobjHalfPallet,CupsAllOff,load0,ApproachHeight(StationHalfPallet),PlaceRetractZone;
            blockState:=BlockPos4;
        CASE BlockPos4:
            ApproachPoint Offs(PlaceHalfPallet,BlockOffsetX,0,layerZ),wobjHalfPallet,CupsAllOff,load0,ApproachHeight(StationHalfPallet),PlaceRetractZone;
            IF box2Layer=Box2MaxLayers THEN
                halfPalletFull:=TRUE;
                SetDO DO_HalfPalletFull,1;
                TPWrite "Half pallet full: replace it, then press the half pallet replaced button";
            ELSEIF linerStackEmpty THEN
                linerMissing:=TRUE;
            ELSE
                PlaceLayerLiner;
            ENDIF
            blockState:=BlockPos1;
        DEFAULT:
            blockState:=BlockPos1;
        ENDTEST
    ENDPROC

    !-----------------------------------------------------------------------
    ! Liner on the layer just finished, then the next layer starts
    !-----------------------------------------------------------------------
    PROC PlaceLayerLiner()
        ApproachPoint Offs(PickLiner,0,0,-(TotalLiners-linersLeft)*LinerHeight),wobjLinerStack,CupsAllOn,loadLiner,ApproachHeight(StationLinerStand),PickRetractZone\pressure:=PressureLiner;
        ApproachPoint Offs(PlaceLiner,0,0,HalfPalletLayerZ()),wobjHalfPallet,CupsAllOff,load0,ApproachHeight(StationHalfPallet),PlaceRetractZone;
        Incr box2Layer;
        Decr linersLeft;
        IF linersLeft=0 THEN
            linerStackEmpty:=TRUE;
            SetDO DO_LinerStackEmpty,1;
            TPWrite "Liner stack empty: refill it, then press the liners refilled button";
        ENDIF
    ENDPROC

    !-----------------------------------------------------------------------
    ! Z of the current layer on the half pallet (block and liner)
    !-----------------------------------------------------------------------
    FUNC num HalfPalletLayerZ()
        ! One liner under every layer except the first one
        RETURN (box2Layer-1)*(Box2Height+LinerHeight);
    ENDFUNC

    !-----------------------------------------------------------------------
    ! Pick or place at a target: approach, vacuum, GripLoad and go up
    !-----------------------------------------------------------------------
    PROC ApproachPoint(robtarget target,PERS wobjdata wobj,bool cups{*},PERS loaddata load,num approachHeight,zonedata exitZone\num pressure)
        ! cups: cups on/off at the target, load: load after the target
        ! exitZone: zone of the retract move (fine after a place, so the robot stops before Main decides)
        ! pressure (optional): given in a pick, it is the vacuum pressure needed to lift the load (bar)
        MoveJ Offs(target,0,0,approachHeight),TransitSpeed,z10,toolVacuum\WObj:=wobj;
        MoveL target,ApproachSpeed,fine,toolVacuum\WObj:=wobj;
        IF Present(pressure) THEN
            ! Pick: valves on and wait for the pressure signal
            GripWithVacuum cups,pressure;
        ELSE
            ! Place: valves off and time to let the vacuum out
            VacuumControl cups;
            WaitTime\InPos,ReleaseTime;
        ENDIF
        GripLoad load;
        MoveL Offs(target,0,0,approachHeight),ApproachSpeed,exitZone,toolVacuum\WObj:=wobj;
    ENDPROC

    !-----------------------------------------------------------------------
    ! Calculation of approach heights (how much the robot goes up over the target)
    !-----------------------------------------------------------------------
    FUNC num ApproachHeight(num station)
        VAR num approachingHeight:=9E+09;
        TEST station
        CASE StationConveyor1:
            approachingHeight:=TransitHeight-ConveyorsHeight-Box1Height;
        CASE StationConveyor2:
            approachingHeight:=TransitHeight-ConveyorsHeight-Box2Height;
        CASE StationTable:
            approachingHeight:=TransitHeight-TableHeight-Box2Height;
        CASE StationLinerStand:
            approachingHeight:=TransitHeight-LinerStandHeight-linersLeft*LinerHeight;
        CASE StationHalfPallet:
            approachingHeight:=TransitHeight-HalfPalletHeight-HalfPalletLayerZ()-Box2Height-PalletOffsetHeight;
            IF approachingHeight<MinApproachHeight THEN
                approachingHeight:=MinApproachHeight;
            ENDIF
        CASE StationEuroPallet:
            approachingHeight:=TransitHeight-EuroPalletHeight-Box1Height*box1Layer-PalletOffsetHeight;
            IF approachingHeight<MinApproachHeight THEN
                approachingHeight:=MinApproachHeight;
            ENDIF
        DEFAULT:
            ! If another station is entered the robot will announce an error trying to reach 9E+09: Safety stop
        ENDTEST
        RETURN approachingHeight;
    ENDFUNC

    !-----------------------------------------------------------------------
    ! Assignment of logical cup signals with physical signals
    !-----------------------------------------------------------------------
    PROC InitSignals()
        ! Call it first: VacuumControl needs it
        AliasIO DO_Cup11,cupSignals{1};
        AliasIO DO_Cup12,cupSignals{2};
        AliasIO DO_Cup13,cupSignals{3};
        AliasIO DO_Cup21,cupSignals{4};
        AliasIO DO_Cup22,cupSignals{5};
        AliasIO DO_Cup23,cupSignals{6};
    ENDPROC

    !-----------------------------------------------------------------------
    ! Valves of the cups: open or close each one (no waiting here)
    !-----------------------------------------------------------------------
    PROC VacuumControl(bool cups{*})

        FOR i FROM 1 TO Dim(cups,1) DO
            IF cups{i} THEN
                SetDO cupSignals{i},1;
            ELSE
                SetDO cupSignals{i},0;
            ENDIF
        ENDFOR
    ENDPROC

    !-----------------------------------------------------------------------
    ! Pick: open the valves and wait until the vacuum pressure is reached
    !-----------------------------------------------------------------------
    PROC GripWithVacuum(bool cups{*},num requiredPressure)
        ! TRUE while the pressure has not been reached (starts TRUE to enter the loop)
        VAR bool timedOut:=TRUE;

        WHILE timedOut DO
            VacuumControl cups;
            ! Robot stopped in position, wait for the analog pressure signal
            WaitUntil\InPos,AI_VacuumPressure>=requiredPressure\MaxTime:=VacuumMaxTime\TimeFlag:=timedOut;
            IF timedOut THEN
                ! Pressure not reached in time: valves off, error to the operator and stop.
                ! After the restart the loop tries the pick again, so the robot never goes up without the load.
                VacuumControl CupsAllOff;
                ErrWrite "Vacuum pressure not reached","Pressure "+NumToStr(AInput(AI_VacuumPressure),1)+" bar, required "+NumToStr(requiredPressure,1)+" bar";
                Stop;
            ENDIF
        ENDWHILE
    ENDPROC

ENDMODULE
