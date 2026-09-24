import("pathfinder.road", "RoadPathFinder", 3);

class MyNewAI extends AIController {
	function Start();
}

function MyNewAI::Start() {

	local max_loan = AICompany.GetMaxLoanAmount();
    AICompany.SetLoanAmount(max_loan);

	AILog.Info("Hello OpenTTD!")
	AICompany.SetName("MyNewAI")
	this.Sleep(50)

	/* list  town all  */
	local townlist = AITownList()

	/* Valuate use population in town */
	townlist.Valuate(AITown.GetPopulation)
	townlist.Sort(AIList.SORT_BY_VALUE, false);

	/* Pick the two towns with the highest population. */
  	local townid_a = townlist.Begin();
  	local townid_b = townlist.Next();

	/* Print the names of the towns we'll try to connect. */
  	AILog.Info("Going to connect " + AITown.GetName(townid_a) + " to " + AITown.GetName(townid_b));

	/* Tell OpenTTD we want to build normal road (no tram tracks). */
  	AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);

	/* Create an instance of the pathfinder. */
  	local pathfinder = RoadPathFinder();

	/* Set the cost for making a turn extreme high. */
  	pathfinder.cost.turn = 5000;

	/* Give the source and goal tiles to the pathfinder. */
  	pathfinder.InitializePath([AITown.GetLocation(townid_a)], [AITown.GetLocation(townid_b)]);

	local path = false;
 	while (path == false) {
    	path = pathfinder.FindPath(100);
    	this.Sleep(1);
  	}

	if (path == null) {
    /* No path was found. */
    	AILog.Error("pathfinder.FindPath return null");
  	}

	  /* If a path was found, build a road over it. */
	while (path != null) {
		local par = path.GetParent();
		if (par != null) {
		local last_node = path.GetTile();
		if (AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) == 1 ) {
			if (!AIRoad.BuildRoad(path.GetTile(), par.GetTile())) {
			/* An error occured while building a piece of road. TODO: handle it. 
			* Note that is can also be the case that the road was already build. */
			}
		} else {
			/* Build a bridge or tunnel. */
			if (!AIBridge.IsBridgeTile(path.GetTile()) && !AITunnel.IsTunnelTile(path.GetTile())) {
			/* If it was a road tile, demolish it first. Do this to work around expended roadbits. */
			if (AIRoad.IsRoadTile(path.GetTile())) AITile.DemolishTile(path.GetTile());
			if (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
				if (!AITunnel.BuildTunnel(AIVehicle.VT_ROAD, path.GetTile())) {
				/* An error occured while building a tunnel. TODO: handle it. */
				}
			} else {
				local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) + 1);
				bridge_list.Valuate(AIBridge.GetMaxSpeed);
				bridge_list.Sort(AIList.SORT_BY_VALUE, false);
				if (!AIBridge.BuildBridge(AIVehicle.VT_ROAD, bridge_list.Begin(), path.GetTile(), par.GetTile())) {
				/* An error occured while building a bridge. TODO: handle it. */
				}
			}
			}
		}
		}
		path = par;
	}
	// ==========================================
    // ฟังก์ชันย่อยสำหรับสแกนหาที่ว่างรอบๆ เมือง
    // ==========================================
    // เราจะเขียนลอจิกวนลูปรอบๆ ใจกลางเมืองเป็นรัศมี 5x5 ช่อง
    // เพื่อหาช่องว่างที่ 1. สร้างสถานีได้ 2. สร้างถนนติดสถานีได้
    
    // (สมมติว่ามีตัวแปร town1_tile และ town2_tile ที่ดึงมาจาก AITown แล้ว)
    local st1_tile = 0; local st1_front = 0;
    local st2_tile = 0; local st2_front = 0;
    local depot_tile = 0; local depot_front = 0;

	local town1_tile = AITown.GetLocation(townid_a);
    local town2_tile = AITown.GetLocation(townid_b);

    AILog.Info("They are scanning the area around the city for vacant land to build the station");

	local FindSpot = function(center_tile) {
        // แก้จุดที่ 2: ดึงพิกัด X, Y ของจุดศูนย์กลางออกมาก่อน
        local center_x = AIMap.GetTileX(center_tile);
        local center_y = AIMap.GetTileY(center_tile);

        for (local x = -3; x <= 3; x++) {
            for (local y = -3; y <= 3; y++) {
                // คำนวณพิกัดใหม่ให้ถูกต้อง
                local test_tile = AIMap.GetTileIndex(center_x + x, center_y + y);
                
                // กันเหนียว: เช็กว่า Tile นั้นไม่ได้อยู่นอกแผนที่
                if (!AIMap.IsValidTile(test_tile)) continue; 

                local test_front = test_tile - 1; 
                
                if (AITile.IsBuildable(test_tile) && AITile.IsBuildable(test_front)) {
                    return [test_tile, test_front];
                }
            }
        }
        return null; 
    };

    // เอาฟังก์ชันไปลองหารอบๆ เมือง 1
    local spot1 = FindSpot(town1_tile);
    if (spot1 != null) {
        st1_tile = spot1[0];
        st1_front = spot1[1];
    } else {
        AILog.Error("Can't find an empty plot of land to build the first city sign!");
    }

    // เอาฟังก์ชันไปลองหารอบๆ เมือง 2
    local spot2 = FindSpot(town2_tile);
    if (spot2 != null) {
        st2_tile = spot2[0];
        st2_front = spot2[1];
    }

    // สร้างอู่รถใกล้ๆ ป้ายเมือง 1 (ขยับไปอีกนิด)
    depot_tile = st1_tile + 2; 
    depot_front = depot_tile - 1;


	// ==============================================================
	AILog.Info("1. Construction of the bus stop and bus depot has begun.");
    
    // สร้างป้ายที่ 1 และดึงรหัสสถานีเก็บไว้
    AIRoad.BuildRoadStation(st1_tile, st1_front, AIRoad.ROADVEHTYPE_BUS, AIStation.STATION_NEW);
    local st1_id = AIStation.GetStationID(st1_tile);

    // สร้างป้ายที่ 2 และดึงรหัสสถานีเก็บไว้
    AIRoad.BuildRoadStation(st2_tile, st2_front, AIRoad.ROADVEHTYPE_BUS, AIStation.STATION_NEW);
    local st2_id = AIStation.GetStationID(st2_tile);

    // สร้างอู่รถ (ต้องสร้างติดถนน ไม่งั้นรถขับออกมาไม่ได้)
    AIRoad.BuildRoadDepot(depot_tile, depot_front);

    AILog.Info("2. Currently selecting a bus from the catalog.");
    
    // ดึงรายชื่อรถทั้งหมดที่เป็นรถถนน (ไม่เอารถไฟ/เรือ)
    local engines = AIEngineList(AIVehicle.VT_ROAD);
    
    // กรองเอาเฉพาะ "รถที่บรรทุกผู้โดยสารได้" (0 คือรหัสสินค้าประเภทผู้โดยสาร)
    engines.Valuate(AIEngine.GetCargoType); 
    engines.KeepValue(0); // เก็บเฉพาะคันที่ได้ค่า 1 (True)
    
    // จัดเรียงตามความเร็วสูงสุด แล้วดึงคันที่เร็วที่สุดมาใช้
    engines.Valuate(AIEngine.GetMaxSpeed);
    engines.Sort(AIList.SORT_BY_VALUE, false);
    local best_bus = engines.Begin();

    AILog.Info("3. Order vehicles and issue work orders.");
    
    // ซื้อรถที่อู่ที่เราสร้างไว้
    local bus_id = AIVehicle.BuildVehicle(depot_tile, best_bus);

    if (AIVehicle.IsValidVehicle(bus_id)) {
        // แจกคิวงานให้รถ (ต้องใช้ Station ID ไม่ใช่พิกัด)
        AIOrder.AppendOrder(bus_id, st1_id, AIOrder.OF_NONE);
        AIOrder.AppendOrder(bus_id, st2_id, AIOrder.OF_NONE);
        
        // สตาร์ทเครื่อง
        AIVehicle.StartStopVehicle(bus_id);
        AILog.Info("The first bus has started running and generating revenue!");
    } else {
        AILog.Error("Car purchase unsuccessful: " + AIError.GetLastErrorString());
    }



	/* Main */
	while (true) {
		this.Sleep(100);
	}
}