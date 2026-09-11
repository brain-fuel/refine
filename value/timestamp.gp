package value

import (
    "fmt"
    "strings"
    "time"
)

// Timestamp preserves the RFC 3339 payload spelling, numeric offset and exact
// fraction. Calendar work uses only UTC; no clock, locale, zone database or I/O
// participates. The zero value is the Unix epoch, not the current time.
type Timestamp struct {
    original string
    second int64
    fraction Number
    leap bool
    offset int
    offsetUnknown bool
}
type TimestampError struct { Code string; Message string }
func (e *TimestampError) Error()string{return e.Code+": "+e.Message}
func timestampError(code,message string)error{return &TimestampError{Code:code,Message:message}}

// The dates are facts from the IERS leap-second table, Bulletin C 72 (2026-07-06).
// The bulletin confirms no December 2026 leap. Future possible leap labels are
// unknown instead of relying on a live fetch or silently accepting speculation.
// Sources: https://hpiers.obspm.fr/iers/bul/bulc/Leap_Second.dat
//          https://hpiers.obspm.fr/iers/bul/bulc/bulletinc.dat
const LeapTableVersion="IERS-C72-2026-07-06"
var leapDates=map[string]bool{
    "1972-06-30":true,"1972-12-31":true,"1973-12-31":true,"1974-12-31":true,
    "1975-12-31":true,"1976-12-31":true,"1977-12-31":true,"1978-12-31":true,
    "1979-12-31":true,"1981-06-30":true,"1982-06-30":true,"1983-06-30":true,
    "1985-06-30":true,"1987-12-31":true,"1989-12-31":true,"1990-12-31":true,
    "1992-06-30":true,"1993-06-30":true,"1994-06-30":true,"1995-12-31":true,
    "1997-06-30":true,"1998-12-31":true,"2005-12-31":true,"2008-12-31":true,
    "2012-06-30":true,"2015-06-30":true,"2016-12-31":true,
}

func timestampDigits(s string)(int,bool){n:=0;for _,c:=range s{if c<'0'||c>'9'{return 0,false};n=n*10+int(c-'0')};return n,true}
func monthDays(year,month int)int {
    switch month{case 4,6,9,11:return 30;case 2:if year%4==0 && (year%100!=0||year%400==0){return 29};return 28}
    return 31
}

// ParseTimestamp accepts the RFC 3339 profile, including lower-case t/z,
// unbounded decimal fractional precision, numeric offsets and known leap labels.
// As with Number parsing, the caller must budget input size before this primitive.
func ParseTimestamp(raw string)(Timestamp,error) {
    invalid:=func()(Timestamp,error){return Timestamp{},timestampError("timestamp.syntax","expected a valid RFC 3339 timestamp")}
    if len(raw)<20 || raw[4]!='-' || raw[7]!='-' || raw[10]!='T'&&raw[10]!='t' || raw[13]!=':' || raw[16]!=':'{return invalid()}
    year,a:=timestampDigits(raw[0:4]);month,b:=timestampDigits(raw[5:7]);day,c:=timestampDigits(raw[8:10])
    hour,d:=timestampDigits(raw[11:13]);minute,f:=timestampDigits(raw[14:16]);second,g:=timestampDigits(raw[17:19])
    if !a||!b||!c||!d||!f||!g || month<1||month>12 || day<1||day>monthDays(year,month) || hour>23||minute>59||second>60{return invalid()}
    index:=19;fraction:=Number{}
    if raw[index]=='.'{
        index++;start:=index
        for index<len(raw) && raw[index]>='0'&&raw[index]<='9'{index++}
        if index==start{return invalid()}
        var err error;fraction,err=ParseNumber("0."+raw[start:index]);if err!=nil{return invalid()}
    }
    if index>=len(raw){return invalid()}
    zone:=raw[index:];offset:=0;unknown:=false
    if zone!="Z" && zone!="z"{
        if len(zone)!=6 || zone[0]!='+'&&zone[0]!='-' || zone[3]!=':'{return invalid()}
        h,ok:=timestampDigits(zone[1:3]);m,ok2:=timestampDigits(zone[4:6]);if !ok||!ok2||h>23||m>59{return invalid()}
        offset=h*60+m;if zone[0]=='-'{offset=-offset;unknown=offset==0}
    }
    base:=time.Date(year,time.Month(month),day,hour,minute,min(second,59),0,time.UTC).Unix()-int64(offset)*60
    leap:=second==60
    if leap{
        utc:=time.Unix(base,0).UTC();date:=fmt.Sprintf("%04d-%02d-%02d",utc.Year(),utc.Month(),utc.Day())
        if utc.Hour()!=23 || utc.Minute()!=59 || utc.Second()!=59 || utc.Day()!=monthDays(utc.Year(),int(utc.Month())){
            return Timestamp{},timestampError("timestamp.leap","leap-second label is not at a UTC month boundary")
        }
        if !leapDates[date]{
            if date>"2026-12-31"{return Timestamp{},timestampError("timestamp.unknown_leap","leap-second occurrence is outside the pinned IERS table")}
            return Timestamp{},timestampError("timestamp.leap","no leap second occurred at this UTC boundary")
        }
    }
    return Timestamp{original:raw,second:base,fraction:fraction,leap:leap,offset:offset,offsetUnknown:unknown},nil
}
func (t Timestamp) Raw()string{if t.original==""{return "1970-01-01T00:00:00Z"};return t.original}
func (t Timestamp) Fraction()Number{return t.fraction}
func (t Timestamp) OffsetMinutes()int{return t.offset}
func (t Timestamp) OffsetKnown()bool{return !t.offsetUnknown}
func (t Timestamp) LeapSecond()bool{return t.leap}

// Compare orders UTC instants, distinguishing a leap second from the following
// midnight. Offset spelling and decimal precision do not alter instant equality.
// -00:00 denotes a known UTC instant with unknown local offset, per RFC 3339 §4.3.
func (t Timestamp) Compare(other Timestamp)int {
    if t.second<other.second{return -1};if t.second>other.second{return 1}
    if t.leap!=other.leap{if t.leap{return 1};return -1}
    return t.fraction.Compare(other.fraction)
}
func (t Timestamp) Equal(other Timestamp)bool{return t.Compare(other)==0}

// Show quotes the retained RFC 3339 representation. This preserves offset
// metadata and original precision across canonical read/show, without rounding.
func (t Timestamp) Show()string{text,_:=TextFromUTF8(t.Raw());return text.Show()}

// CivilSecondsUntil is explicit civil-coordinate arithmetic, not an assertion
// about elapsed SI seconds. It excludes inserted leap seconds between endpoints
// and refuses a leap-labelled endpoint, which has no unique ordinary coordinate.
func (t Timestamp) CivilSecondsUntil(other Timestamp)(Number,error) {
    if t.leap||other.leap{return Number{},timestampError("timestamp.civil_leap","civil-coordinate subtraction cannot represent a leap-labelled endpoint")}
    return Integer(other.second-t.second).Add(other.fraction.Subtract(t.fraction)),nil
}

// SISecondsUntil includes leap seconds in the pinned history. Outside the
// post-1972, announced interval, a physical elapsed duration is unknown; civil
// coordinate arithmetic remains available under its explicit name above.
func (t Timestamp) SISecondsUntil(other Timestamp)(Number,error) {
    start:=time.Date(1972,1,1,0,0,0,0,time.UTC).Unix()
    end:=time.Date(2027,1,1,0,0,0,0,time.UTC).Unix()
    if t.second<start||other.second<start||t.second>end||other.second>end || t.second==end&&t.fraction.Sign()!=0 || other.second==end&&other.fraction.Sign()!=0{
        return Number{},timestampError("timestamp.history_unknown","elapsed SI duration is outside the pinned leap-second history")
    }
    coordinate:=func(x Timestamp)Number{
        date:=time.Unix(x.second,0).UTC().Format("2006-01-02")
        count:=int64(0);for boundary:=range leapDates{if strings.Compare(boundary,date)<0{count++}}
        if x.leap{count++}
        return Integer(x.second+count).Add(x.fraction)
    }
    return coordinate(other).Subtract(coordinate(t)),nil
}
