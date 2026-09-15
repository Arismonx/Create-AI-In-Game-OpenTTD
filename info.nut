class MyNewAI extends AIInfo {
  function GetAuthor()      { return "Arismonx"; }
  function GetName()        { return "MyNewAI"; }
  function GetDescription() { return "My first Ai in OpenTTD and An example AI by following the tutorial at http://wiki.openttd.org/"; }
  function GetVersion()     { return 1; }
  function GetDate()        { return "2026-09-15"; }
  function CreateInstance() { return "MyNewAI"; }
  function GetShortName()   { return "MFAI"; }
  function GetAPIVersion()  { return "12"; }
}

/* Tell the core we are an AI */
RegisterAI(MyNewAI());