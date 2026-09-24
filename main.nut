import("pathfinder.road", "RoadPathFinder", 3);

class MyNewAI extends AIController {
	function Start();
	function FindSpot(center_tile);
	function FindRoute(towns);
	function BuildPath(path);
	function BuildStation(spot);
	function PickBus();
}

/* Cluster scan: needs 4 flat, buildable tiles in a row along X:
 * [depot][depot_front][station][station_front]
 * The search radius grows step by step until a spot is found. */
function MyNewAI::FindSpot(center_tile) {
	local cx = AIMap.GetTileX(center_tile);
	local cy = AIMap.GetTileY(center_tile);

	foreach (radius in [3, 5, 7, 10]) {
		for (local x = -radius; x <= radius; x++) {
			for (local y = -radius; y <= radius; y++) {
				local t = AIMap.GetTileIndex(cx + x, cy + y);
				if (!AIMap.IsValidTile(t)) continue;

				local ok = true;
				for (local i = 0; i < 4; i++) {
					local n = t + i;
					if (!AIMap.IsValidTile(n) || AIMap.GetTileY(n) != cy + y ||
						!AITile.IsBuildable(n) || AITile.GetSlope(n) != AITile.SLOPE_FLAT) {
						ok = false;
						break;
					}
				}
				if (ok) {
					return {depot = t, depot_front = t + 1, station = t + 2, front = t + 3};
				}
			}
		}
		AILog.Info("No spot within radius " + radius + ", expanding search");
	}
	return null;
}

/* Try town pairs (top-populated first) until a spot pair and a path are found. */
function MyNewAI::FindRoute(towns) {
	for (local i = 0; i < towns.len(); i++) {
		for (local j = i + 1; j < towns.len(); j++) {
			local a = towns[i];
			local b = towns[j];
			AILog.Info("Trying " + AITown.GetName(a) + " -> " + AITown.GetName(b));

			local spot1 = this.FindSpot(AITown.GetLocation(a));
			if (spot1 == null) { AILog.Warning("No vacant land near " + AITown.GetName(a)); continue; }
			local spot2 = this.FindSpot(AITown.GetLocation(b));
			if (spot2 == null) { AILog.Warning("No vacant land near " + AITown.GetName(b)); continue; }

			/* Build stations first so the pathfinder treats them as obstacles. */
			if (!this.BuildStation(spot1) || !this.BuildStation(spot2)) {
				AILog.Warning("Station construction failed, trying the next pair");
				continue;
			}

			local pathfinder = RoadPathFinder();
			pathfinder.cost.turn = 5000;
			pathfinder.InitializePath([spot1.front], [spot2.front]);

			local path = false;
			local tries = 0;
			while (path == false && tries < 200) {
				path = pathfinder.FindPath(100);
				tries++;
				this.Sleep(1);
			}

			if (path == false || path == null) {
				AILog.Warning("No path between these towns, trying the next pair");
				continue;
			}
			return {spot1 = spot1, spot2 = spot2, path = path};
		}
	}
	return null;
}

function MyNewAI::BuildPath(path) {
	while (path != null) {
		local par = path.GetParent();
		if (par != null) {
			if (AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) == 1) {
				if (!AIRoad.BuildRoad(path.GetTile(), par.GetTile())) {
					/* May also just mean the road already exists. */
					local err = AIError.GetLastError();
					if (err != AIError.ERR_ALREADY_BUILT) {
						AILog.Warning("BuildRoad failed: " + AIError.GetLastErrorString());
					}
				}
			} else if (!AIBridge.IsBridgeTile(path.GetTile()) && !AITunnel.IsTunnelTile(path.GetTile())) {
				if (AIRoad.IsRoadTile(path.GetTile())) AITile.DemolishTile(path.GetTile());
				if (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
					if (!AITunnel.BuildTunnel(AIVehicle.VT_ROAD, path.GetTile())) {
						AILog.Warning("BuildTunnel failed: " + AIError.GetLastErrorString());
						return false;
					}
				} else {
					local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) + 1);
					bridge_list.Valuate(AIBridge.GetMaxSpeed);
					bridge_list.Sort(AIList.SORT_BY_VALUE, false);
					if (!AIBridge.BuildBridge(AIVehicle.VT_ROAD, bridge_list.Begin(), path.GetTile(), par.GetTile())) {
						AILog.Warning("BuildBridge failed: " + AIError.GetLastErrorString());
						return false;
					}
				}
			}
		}
		path = par;
	}
	return true;
}

/* Builds the drive-through station and the depot next to it. */
function MyNewAI::BuildStation(spot) {
	if (!AIRoad.BuildDriveThroughRoadStation(spot.station, spot.front, AIRoad.ROADVEHTYPE_BUS, AIStation.STATION_NEW)) {
		AILog.Error("Station construction failed: " + AIError.GetLastErrorString());
		return false;
	}
	if (!AIRoad.BuildRoadDepot(spot.depot, spot.depot_front)) {
		AILog.Error("Depot construction failed: " + AIError.GetLastErrorString());
		return false;
	}
	/* The depot only faces depot_front; the road bit toward it must be built explicitly. */
	if (!AIRoad.BuildRoad(spot.depot_front, spot.depot)) {
		if (AIError.GetLastError() != AIError.ERR_ALREADY_BUILT) {
			AILog.Error("Depot entrance road failed: " + AIError.GetLastErrorString());
			return false;
		}
	}
	/* Road bit from the front tile into the station (the pathfinder only builds along its route). */
	if (!AIRoad.BuildRoad(spot.station, spot.front)) {
		if (AIError.GetLastError() != AIError.ERR_ALREADY_BUILT) {
			AILog.Error("Station front road failed: " + AIError.GetLastErrorString());
			return false;
		}
	}
	/* Link depot front to the station tile. */
	if (!AIRoad.BuildRoad(spot.depot_front, spot.station)) {
		if (AIError.GetLastError() != AIError.ERR_ALREADY_BUILT) {
			AILog.Error("Depot road failed: " + AIError.GetLastErrorString());
			return false;
		}
	}
	return true;
}

function MyNewAI::PickBus() {
	local pass = null;
	local cargos = AICargoList();
	foreach (c, _ in cargos) {
		if (AICargo.HasCargoClass(c, AICargo.CC_PASSENGERS)) { pass = c; break; }
	}
	if (pass == null) return null;

	local engines = AIEngineList(AIVehicle.VT_ROAD);
	engines.Valuate(AIEngine.GetCargoType);
	engines.KeepValue(pass);
	engines.Valuate(AIEngine.GetMaxSpeed);
	engines.Sort(AIList.SORT_BY_VALUE, false);
	if (engines.Count() == 0) return null;
	return engines.Begin();
}

function MyNewAI::Start() {
	AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
	AICompany.SetName("Tus Transport Co.");
	AILog.Info("Hello OpenTTD!");
	this.Sleep(50);

	AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);

	/* Take the 5 most populated towns as candidates. */
	local townlist = AITownList();
	townlist.Valuate(AITown.GetPopulation);
	townlist.Sort(AIList.SORT_BY_VALUE, false);
	local towns = [];
	foreach (t, _ in townlist) {
		towns.append(t);
		if (towns.len() >= 5) break;
	}

	local route = this.FindRoute(towns);
	if (route == null) {
		AILog.Error("No usable route found between any towns, stopping.");
		return;
	}

	if (!this.BuildPath(route.path)) {
		AILog.Error("Road construction failed, stopping.");
		return;
	}

	AILog.Info("1. Selecting a bus.");
	local bus = this.PickBus();
	if (bus == null) {
		AILog.Error("No passenger road vehicle available, stopping.");
		return;
	}

	AILog.Info("2. Buying vehicle and issuing orders.");
	local bus_id = AIVehicle.BuildVehicle(route.spot1.depot, bus);
	if (!AIVehicle.IsValidVehicle(bus_id)) {
		AILog.Error("Car purchase unsuccessful: " + AIError.GetLastErrorString());
		return;
	}

	/* Orders take tile indexes, not station ids. */
	AIOrder.AppendOrder(bus_id, route.spot1.station, AIOrder.OF_NONE);
	AIOrder.AppendOrder(bus_id, route.spot2.station, AIOrder.OF_NONE);
	AIVehicle.StartStopVehicle(bus_id);
	AILog.Info("The first bus has started running!");

	while (true) {
		this.Sleep(100);
	}
}