class MyNewAI extends AIController {
	function Start();
}

function MyNewAI::Start() {
	AILog.Info("Hello OpenTTD!")
	AICompany.SetName("MyNewAI")
	this.Sleep(50)

	/* list  town all  */
	local townlist = AITownList()

	/* Valuate use population in town */
	townlist.Valuate(AITown.GetPopulation)
	townlist.Sort(AIList.SORT_BY_VALUE, false);

	/* loop list */
	for (local town_id = townlist.Begin(); !townlist.IsEnd(); town_id = townlist.Next()) {
		local name = AITown.GetName(town_id)
		local population = townlist.GetValue(town_id)

		AILog.Info("Town: " + name + "(Population: " + population + ")")
	}
	AILog.Info("End loop!")

	/* Main */
	while (true) {
		this.Sleep(100);
	}
}