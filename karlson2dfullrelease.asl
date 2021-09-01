state("Karlson")
{
    string250 levelName : "UnityPlayer.dll",0x01683318, 0x48, 0x10, 0x0;
    long levelAddress : "UnityPlayer.dll", 0x1683318, 0x48, 0x10;
}
startup
{
    vars.gameTarget = new SigScanTarget("EC 08 48 89 0C 24 48 B8");
    vars.playerMovementTarget = new SigScanTarget("48 89 75 F8 48 8B F1 48 B8 ?? ?? ?? ?? ?? ?? ?? ?? 48 89 30 48 B9");
    vars.winConditionTarget = new SigScanTarget("48 89 30 C7 46 20 00 00 00 00");
    vars.scanCooldown = new Stopwatch();
    vars.SetTextComponent = (Action<string, string>)((id, text) =>
	{
        var textSettings = timer.Layout.Components.Where(x => x.GetType().Name == "TextComponent").Select(x => x.GetType().GetProperty("Settings").GetValue(x, null));
        var textSetting = textSettings.FirstOrDefault(x => (x.GetType().GetProperty("Text1").GetValue(x, null) as string) == id);
        if (textSetting == null)
        {
            var textComponentAssembly = Assembly.LoadFrom("Components\\LiveSplit.Text.dll");
            var textComponent = Activator.CreateInstance(textComponentAssembly.GetType("LiveSplit.UI.Components.TextComponent"), timer);
            timer.Layout.LayoutComponents.Add(new LiveSplit.UI.Components.LayoutComponent("LiveSplit.Text.dll", textComponent as LiveSplit.UI.Components.IComponent));
            textSetting = textComponent.GetType().GetProperty("Settings", BindingFlags.Instance | BindingFlags.Public).GetValue(textComponent, null);
            textSetting.GetType().GetProperty("Text1").SetValue(textSetting, id);
        }
        if (textSetting != null)
            textSetting.GetType().GetProperty("Text2").SetValue(textSetting, text);
	});
    if (timer.CurrentTimingMethod == TimingMethod.RealTime)
{
    var timingMessage = MessageBox.Show(
        "This game uses RTA w/o Loads as the main timing method.\n"
        + "LiveSplit is currently set to show Real Time (RTA).\n"
        + "Would you like to set the timing method to RTA w/o Loads",
        "Karlson2D | LiveSplit",
        MessageBoxButtons.YesNo, MessageBoxIcon.Question
    );
    if (timingMessage == DialogResult.Yes)
    {
        timer.CurrentTimingMethod = TimingMethod.GameTime;
    }
}
}

init
{
    vars.playerMovementPtr = IntPtr.Zero;
    vars.winConditionPtr = IntPtr.Zero;
    var gamePtr = IntPtr.Zero;

    vars.kills = new MemoryWatcher<int>(IntPtr.Zero);
    vars.requiredKills = new MemoryWatcher<int>(IntPtr.Zero);
    vars.dead = new MemoryWatcher<bool>(IntPtr.Zero);

    if(!vars.scanCooldown.IsRunning)
    {
        vars.scanCooldown.Start(); 
    }

    var timeSinceLastInit = vars.scanCooldown.Elapsed.TotalMilliseconds;

    if(timeSinceLastInit >= 1000) 
    {
        
        foreach (var page in game.MemoryPages(true))
        {
            var scanner = new SignatureScanner(game, page.BaseAddress, (int)page.RegionSize);
            if(gamePtr == IntPtr.Zero)
                gamePtr = scanner.Scan(vars.gameTarget);
            if(gamePtr != IntPtr.Zero)
                break;
        }

        if(gamePtr == IntPtr.Zero) 
        {
            vars.scanCooldown.Restart();
            throw new Exception("game pointer not found - resetting");
        }
        else 
        {
            vars.scanCooldown.Reset();
        }
    }
    else 
    {
        throw new Exception("init not ready");
    }

    print("game pointer found");

    
    var startedPtr = new DeepPointer(gamePtr+0x8, 0x0, 0x18); 
    var pausedPtr = new DeepPointer(gamePtr+0x8, 0x0, 0x19); 
                                                                    
    vars.started = new MemoryWatcher<bool>(startedPtr);
    vars.paused = new MemoryWatcher<bool>(pausedPtr);
    vars.watchers = new MemoryWatcherList() {vars.started, vars.paused};
    
}

update
{
    vars.watchers.UpdateAll(game);

    if((vars.winConditionPtr == IntPtr.Zero || vars.playerMovementPtr == IntPtr.Zero) && vars.started.Old)
    {
        print("looking for secondary pointers");
        foreach (var page in game.MemoryPages(true))
        {
            var scanner = new SignatureScanner(game, page.BaseAddress, (int)page.RegionSize);
            if(vars.winConditionPtr == IntPtr.Zero)
                vars.winConditionPtr = scanner.Scan(vars.winConditionTarget);
            if(vars.playerMovementPtr == IntPtr.Zero)
                vars.playerMovementPtr = scanner.Scan(vars.playerMovementTarget);
            if(vars.winConditionPtr != IntPtr.Zero && vars.playerMovementPtr != IntPtr.Zero)
            {
                print("found secondary pointers");
                var killsPointer = new DeepPointer(vars.winConditionPtr-0x8, 0x0, 0x20);
                var requiredKillsPointer = new DeepPointer(vars.winConditionPtr-0x8, 0x0, 0x24);
                var deadPointer = new DeepPointer(vars.playerMovementPtr+0x9, 0x0, 0x99);
                
                vars.kills = new MemoryWatcher<int>(killsPointer);
                vars.requiredKills = new MemoryWatcher<int>(requiredKillsPointer);
                vars.dead = new MemoryWatcher<bool>(deadPointer);

                vars.watchers = new MemoryWatcherList() {vars.started, vars.paused, vars.kills, vars.requiredKills, vars.dead};
                break;
            }
        }
    }
}

start
{
    if(current.levelName == "Assets/Scenes/Stages/Stage0.unity" && old.levelName == "Assets/Scenes/Stages/Lobby.unity")
    {
        return true;
    } else
    {
        return(current.levelAddress != old.levelAddress && current.levelName == "Assets/Scenes/Stages/Stage0.unity");
    }

}

split
{
    if(vars.kills.Current == vars.requiredKills.Current && vars.kills.Old < vars.requiredKills.Current && vars.requiredKills.Current != 0 && !vars.dead.Current)
    {
        return true;
    } else
    {
        return false;
    }
}

isLoading
{
    print(vars.kills.Current.ToString() + vars.requiredKills.Current.ToString());
    return(vars.dead.Current || vars.kills.Current == vars.requiredKills.Current || !vars.started.Current);
}

reset
{
    if(current.levelAddress != old.levelAddress)
    {
        return(current.levelName == "Assets/Scenes/Stages/Stage0.unity");
    } else
    {
        return false;
    }
}
