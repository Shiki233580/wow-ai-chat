namespace WhaleChat;

// Runtime fault is distinct from the user's persisted pause preference.
internal sealed class ConnectionGate
{
    string session="";
    int nonce;
    internal bool Faulted { get; private set; }
    internal string Error { get; private set; }="";
    internal void Fail(string reason) { Faulted=true;Error=reason; }
    internal void ClearFault() { Faulted=false;Error=""; }
    internal bool RecoverAutomatically(bool packetValid,bool idle,bool keysUp,bool unrelatedFocus,bool manuallyPaused)
    {
        if(!Faulted || !packetValid || !keysUp || unrelatedFocus || manuallyPaused) return false;
        ClearFault();return true;
    }
    internal bool ObserveReconnect(string currentSession,int requestNonce)
    {
        if(string.IsNullOrEmpty(currentSession)||requestNonce<0)return false;
        if(currentSession!=session) { session=currentSession;nonce=requestNonce;return false; }
        if(requestNonce<=nonce)return false;
        nonce=requestNonce;return true;
    }
}

internal static class ConnectionGateTests
{
    internal static void Run(Action<string,bool> check)
    {
        var config=new Config();var gate=new ConnectionGate();
        check("fresh install defaults to automatic connection",!config.paused&&!gate.Faulted);
        check("initial stale reconnect packet cannot resume pause",!gate.ObserveReconnect("session1",3));
        gate.Fail("focus changed");
        check("transport fault does not change persisted manual pause",gate.Faulted&&!config.paused);
        check("unchanged packet never retries faulted operation",!gate.ObserveReconnect("session1",3)&&gate.Faulted);
        check("new panel click requests reconnect",gate.ObserveReconnect("session1",4));
        gate.ClearFault();check("explicit reconnect clears runtime fault",!gate.Faulted&&gate.Error=="");
        check("replayed and older clicks ignored",!gate.ObserveReconnect("session1",4)&&!gate.ObserveReconnect("session1",2));
        config.paused=true;gate.Fail("timeout");gate.ClearFault();
        check("clearing fault alone never overrides manual pause",config.paused);
        check("reload packet establishes new baseline not implicit resume",!gate.ObserveReconnect("session2",0)&&config.paused);
        check("panel click after reload detected",gate.ObserveReconnect("session2",1));
        check("invalid reconnect packets ignored",!gate.ObserveReconnect("",9)&&!gate.ObserveReconnect("session2",-1));
        gate.Fail("user keys");check("manual pause never auto-resumes",!gate.RecoverAutomatically(true,true,true,false,true)&&gate.Faulted);
        check("held keys defer automatic recovery",!gate.RecoverAutomatically(true,true,false,false,false)&&gate.Faulted);
        check("unrelated typing defers automatic recovery",!gate.RecoverAutomatically(true,true,true,true,false)&&gate.Faulted);
        check("valid idle state automatically clears fault",gate.RecoverAutomatically(true,true,true,false,false)&&!gate.Faulted);
        check("zero cooldown default honored",new Config().cooldownSeconds==0);
        check("unlimited hourly default",new Config().hourlyLimit==0);
        gate.Fail("interrupted");check("mouse motion does not block automatic recovery",gate.RecoverAutomatically(true,false,true,false,false)&&!gate.Faulted);

    }
}
