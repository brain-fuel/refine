package value

import (
    "encoding/json"
    "fmt"
    "os"
    "strings"
    "testing"
    "testing/quick"
    "time"
)

func timestamp(t *testing.T,raw string)Timestamp{t.Helper();v,err:=ParseTimestamp(raw);if err!=nil{t.Fatal(err)};return v}

func TestTimestampConformance(t *testing.T){
    raw,err:=os.ReadFile("testdata/timestamps.json");if err!=nil{t.Fatal(err)}
    var cases []struct{Text string;Code string;Fraction string;Offset int;Known bool;Leap bool}
    if err:=json.Unmarshal(raw,&cases);err!=nil{t.Fatal(err)}
    for _,tc:=range cases{t.Run(tc.Text,func(t *testing.T){
        v,err:=ParseTimestamp(tc.Text)
        if tc.Code!=""{if err==nil||err.(*TimestampError).Code!=tc.Code{t.Fatalf("got %v, want %s",err,tc.Code)};if strings.Contains(err.Error(),tc.Text){t.Fatal("private payload in error")};return}
        if err!=nil{t.Fatal(err)}
        if v.Raw()!=tc.Text||v.Fraction().Show()!=tc.Fraction||v.OffsetMinutes()!=tc.Offset||v.OffsetKnown()!=tc.Known||v.LeapSecond()!=tc.Leap{t.Fatalf("wrong value: %+v",v)}
        text,err:=ReadText(v.Show());if err!=nil{t.Fatal(err)};read,err:=text.UTF8();if err!=nil||read!=tc.Text{t.Fatal("read/show changed payload")}
    })}
    zero:=Timestamp{};epoch:=timestamp(t,"1970-01-01T00:00:00Z")
    if !zero.Equal(epoch)||zero.Raw()!=epoch.Raw()||zero.Show()!=epoch.Show(){t.Fatal("zero timestamp is not epoch")}
}

func TestTimestampOrderingAndDurations(t *testing.T){
    left:=timestamp(t,"1990-12-31T23:59:60.25Z");right:=timestamp(t,"1990-12-31T15:59:60.2500-08:00")
    if !left.Equal(right)||left.Raw()==right.Raw(){t.Fatal("instant equality must not overwrite offset/precision")}
    if !timestamp(t,"2026-09-11T00:00:00-00:00").Equal(timestamp(t,"2026-09-11T00:00:00Z")){t.Fatal("unknown local offset lost known UTC instant")}
    ordered:=[]string{"2016-12-31T23:59:59.999999999999999Z","2016-12-31T23:59:60Z","2016-12-31T23:59:60.5Z","2017-01-01T00:00:00Z"}
    for i,a:=range ordered{for j,b:=range ordered{x,y:=timestamp(t,a),timestamp(t,b);want:=0;if i<j{want=-1};if i>j{want=1};if x.Compare(y)!=want{t.Fatalf("order %s %s",a,b)}}}
    for _,tc:=range []struct{a string;b string;si string;civil string}{
        {"2016-12-31T23:59:59Z","2016-12-31T23:59:60Z","1",""},
        {"2016-12-31T23:59:60Z","2017-01-01T00:00:00Z","1",""},
        {"2016-12-31T23:59:59.75Z","2017-01-01T00:00:00.25Z","3/2","1/2"},
        {"1972-01-01T00:00:00Z","2017-01-01T00:00:00Z","1420156827","1420156800"},
        {"2026-12-31T23:59:59Z","2027-01-01T00:00:00Z","1","1"},
    }{
        a,b:=timestamp(t,tc.a),timestamp(t,tc.b);si,err:=a.SISecondsUntil(b);if err!=nil||si.Show()!=tc.si{t.Fatalf("SI %s: %s %v",tc.a,si.Show(),err)}
        reverse,err:=b.SISecondsUntil(a);if err!=nil||reverse.Add(si).Sign()!=0{t.Fatal("duration antisymmetry")}
        civil,err:=a.CivilSecondsUntil(b);if tc.civil==""{if err==nil{t.Fatal("ambiguous civil leap coordinate")}}else if err!=nil||civil.Show()!=tc.civil{t.Fatalf("civil %s: %s %v",tc.a,civil.Show(),err)}
    }
    for _,raw:=range []string{"1971-12-31T23:59:59Z","2027-01-01T00:00:00.0000000001Z","2100-01-01T00:00:00Z"}{
        if _,err:=left.SISecondsUntil(timestamp(t,raw));err==nil||err.(*TimestampError).Code!="timestamp.history_unknown"{t.Fatal("invented SI history")}
    }
}

func TestTimestampOffsetProperties(t *testing.T){
    property:=func(second uint32,nanos uint32,offset int16)bool{
        // Ordinary instants: independent host calendar/offset oracle, restricted
        // to nanoseconds only here. Conformance fixtures cover finer precision.
        instant:=time.Unix(int64(second),int64(nanos%1000000000)).UTC()
        minutes:=int(offset)%1440
        local:=instant.Add(time.Duration(minutes)*time.Minute)
        sign:="+";absolute:=minutes;if absolute<0{sign="-";absolute=-absolute}
        raw:=local.Format("2006-01-02T15:04:05.000000000")+fmt.Sprintf("%s%02d:%02d",sign,absolute/60,absolute%60)
        a,err:=ParseTimestamp(raw);if err!=nil{return false}
        b,err:=ParseTimestamp(instant.Format(time.RFC3339Nano));if err!=nil{return false}
        shown,err:=ReadText(a.Show());if err!=nil{return false};round,err:=shown.UTF8()
        return err==nil&&round==raw&&a.Equal(b)&&a.OffsetMinutes()==minutes
    }
    if err:=quick.Check(property,&quick.Config{MaxCount:5000});err!=nil{t.Fatal(err)}
}

func FuzzTimestampReadShow(f *testing.F){
    for _,raw:=range []string{"2000-02-29T00:00:00Z","2016-12-31T23:59:60.123456789012345Z","2027-06-30T23:59:60Z","0000-01-01t00:00:00-00:00","2026-01-01T00:00:00."}{f.Add(raw)}
    f.Fuzz(func(t *testing.T,raw string){
        if len(raw)>2000{t.Skip()};v,err:=ParseTimestamp(raw);again,err2:=ParseTimestamp(raw)
        if (err==nil)!=(err2==nil){t.Fatal("nondeterministic parse")};if err!=nil{if err.Error()!=err2.Error(){t.Fatal("nondeterministic error")};return}
        if v.Raw()!=raw||!v.Equal(again){t.Fatal("changed raw value")}
        text,err:=ReadText(v.Show());if err!=nil{t.Fatal(err)};back,err:=text.UTF8();if err!=nil||back!=raw{t.Fatal("show/read mismatch")}
    })
}
