package java

import (
    "bytes"
    "context"
    "fmt"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"
    "time"

    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

const unionModelContract = `
type Amount = Int where it >= 0 @code "amount.nonnegative"
type CardDetails = { name :: String, amount :: Amount }
data Payment = Cash Amount | Card CardDetails | Split Amount Amount | Free
total :: Payment -> Int
total (Cash value) = value
total (Card detail) = detail.amount
total (Split left right) = left + right
total Free = 0
type Paid = Payment where total it > 0 @code "payment.positive"
type Large = Paid where total it >= 100 @code "payment.large"
type Bounded = Payment where total it <= 10 @code "payment.bounded"
type Ordered = Payment where (case it of { Split a b -> a < b; _ -> True }) @code "payment.ordered"
type Unknown = Payment where 1 / 0 > 0.0
type Envelope = { payment :: Paid, alternatives :: [Payment], optional :: Maybe Payment }
data Tree = Leaf Int | Branch Tree Tree
positive :: Tree -> Bool
positive (Leaf n) = n >= 0
positive (Branch left right) = positive left && positive right
type PositiveTree = Tree where positive it
data Token = Token String
data Collision = String Int | Draft Int | Data Bool
type Marker = String
data NameClash = Marker Int | Marker_ Int
`

func TestGeneratedUnionModels(t *testing.T){
    compiler,vm:=javaTools(t);dependencies:=jetCheckClasspath(t);program,err:=language.Compile(unionModelContract);if err!=nil{t.Fatal(err)}
    files,err:=GenerateModels(program,"example.unions","Contract");if err!=nil{t.Fatal(err)}
    root:=t.TempDir();sources:=[]string{}
    for _,file:=range files{target:=filepath.Join(root,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    proof:=filepath.Join(root,"example","unions","UnionProof.java")
    if err:=os.WriteFile(proof,[]byte(unionProofJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,proof)
    harness:=filepath.Join(root,"UnionConformance.java");if err:=os.WriteFile(harness,[]byte(unionModelHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness)
    classes:=filepath.Join(root,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",dependencies,"-d",classes},sources...)
    if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("javac: %v\n%s",err,output)}
    vectors:=[]vector{}
    add:=func(mode,name,constructor string,a,b int64,total,clause uint64){
        av,bv:=value.OfNumber(value.Integer(a)),value.OfNumber(value.Integer(b));data:=testVariant(constructor)
        switch constructor{case "Cash","Leaf":data=testVariant(constructor,av);case "Split":data=testVariant(constructor,av,bv);case "Card":data=testVariant(constructor,testRecord(value.DataField{Name:"name",Value:testText("Account")},value.DataField{Name:"amount",Value:av}));case "Branch":data=testVariant(constructor,testVariant("Leaf",av),testVariant("Leaf",bv))}
        limits:=validation.Limits{Total:total,Clause:clause};var report validation.Report;canonical:=""
        switch mode{
        case "bypass":report=program.ValidateDataWithoutRefinements(name,data,limits)
        case "read":shown,err:=language.ShowDataWithoutValidation(data,validation.Limits{});if err!=nil{t.Fatal(err)};canonical=readUnits(shown);_,report=program.ReadData(name,shown,limits)
        default:report=program.ValidateData(name,data,limits)
        }
        vectors=append(vectors,vector{fmt.Sprintf("%s\t%s\t%s\t%d\t%d\t%d\t%d\t%s",mode,name,constructor,a,b,total,clause,canonical),reportLine(report)})
    }
    for _,name:=range []string{"Payment","Paid","Large","Bounded","Ordered","Unknown"}{for _,constructor:=range []string{"Cash","Card","Split","Free","Missing"}{for _,n:=range []int64{-1,0,1,9,10,99,100,101}{for _,mode:=range []string{"validate","bypass","read"}{add(mode,name,constructor,n,n+1,0,0)}}}}
    for _,name:=range []string{"Tree","PositiveTree"}{for _,constructor:=range []string{"Leaf","Branch","Missing"}{for _,n:=range []int64{-1,0,1}{for _,mode:=range []string{"validate","bypass","read"}{add(mode,name,constructor,n,n+1,0,0)}}}}
    for _,name:=range []string{"Payment","Paid","Large","Unknown","Ordered"}{for _,constructor:=range []string{"Cash","Split","Free"}{for n:=uint64(1);n<400;n++{add("validate",name,constructor,1,2,n,0);add("validate",name,constructor,0,0,0,n);add("read",name,constructor,1,2,n,0)}}}
    var input strings.Builder;for _,v:=range vectors{input.WriteString(v.input);input.WriteByte('\n')}
    ctx,cancel:=context.WithTimeout(context.Background(),3*time.Minute);defer cancel();command:=exec.CommandContext(ctx,vm,"-Xss256k","-cp",classes+string(os.PathListSeparator)+dependencies,"UnionConformance");command.Stdin=strings.NewReader(input.String());var stderr bytes.Buffer;command.Stderr=&stderr
    output,err:=command.Output();if err!=nil{t.Fatalf("Java union models: %v\n%s",err,stderr.String())}
    lines:=strings.Split(strings.TrimSuffix(string(output),"\n"),"\n");if len(lines)!=len(vectors){t.Fatalf("expected %d outputs, got %d",len(vectors),len(lines))}
    for i,v:=range vectors{if lines[i]!=v.expected{t.Fatalf("case %s\nJava %s\nGo   %s",v.input,lines[i],v.expected)}}
    for _,source:=range []string{
        `import example.unions.*; class Wrong { Paid value = new Payment.Free(); }`,
        `import example.unions.*; class Wrong { Bounded value = new Large.Cash(new Amount(java.math.BigInteger.valueOf(100))); }`,
        `import example.unions.*; abstract class Wrong implements Payment {}`,
        `import example.unions.*; abstract class Wrong implements Payment.Variant {}`,
    }{
        target:=filepath.Join(root,"Wrong.java");if err:=os.WriteFile(target,[]byte(source),0644);err!=nil{t.Fatal(err)}
        output,err:=exec.Command(compiler,"--release","25","-cp",classes,target).CombinedOutput()
        if err==nil||!(strings.Contains(string(output),"incompatible types")||strings.Contains(string(output),"not allowed to extend sealed")){t.Fatalf("nominal/sealed negative compilation: %v\n%s",err,output)}
    }
    t.Logf("%d complete report/read comparisons, union model API checks and 6000 jetCheck cases passed",len(vectors))
}

const unionProofJava = `
package example.unions;
public final class UnionProof {
    static void rejects(Runnable action) {
        try { action.run(); throw new AssertionError("foreign evidence accepted"); }
        catch (IllegalArgumentException | ValidationException expected) {}
    }
    public static void run() {
        var raw = new Data.Variant("Cash",java.util.List.of(new Data.Number(Rational.of(100))));
        var parent = ModelSupport.validate("Payment",raw,Budget.Limits.defaults());
        rejects(() -> new Paid.Cash(parent));
        var child = ModelSupport.validate("Large",raw,Budget.Limits.defaults());
        if (new Payment.Cash(child).rawData()!=raw || new Paid.Cash(child).rawData()!=raw) throw new AssertionError();
        rejects(() -> new Bounded.Cash(child));
        rejects(() -> new Payment.Free(child));
    }
}
`

const unionModelHarnessJava = `
import example.unions.*;
import java.util.List;
import java.util.Locale;
import java.util.HexFormat;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import org.jetbrains.jetCheck.Generator;
import org.jetbrains.jetCheck.PropertyChecker;
public final class UnionConformance {
    static void require(boolean value){if(!value)throw new AssertionError();}
    static String hex(String text){return HexFormat.of().formatHex(text.getBytes(StandardCharsets.UTF_8));}
    static String units(String text){var out=new StringBuilder();for(int i=0;i<text.length();i+=4)out.append((char)Integer.parseInt(text.substring(i,i+4),16));return out.toString();}
    static void rejects(Runnable action){try{action.run();throw new AssertionError("invalid union accepted");}catch(ValidationException expected){}}
    static Data number(long n){return new Data.Number(Rational.of(n));}
    static Amount amount(long n){return new Amount(BigInteger.valueOf(n));}
    static BigInteger total(Payment payment){
        return switch(payment.variant()){
            case Payment.Cash cash -> cash.value().value();
            case Payment.Card card -> card.value().amount().value();
            case Payment.Split split -> split.value1().value().add(split.value2().value());
            case Payment.Free ignored -> BigInteger.ZERO;
        };
    }
    static String branch(Paid payment){return switch(payment.variant()){case Payment.Cash ignored->"Cash";case Payment.Card ignored->"Card";case Payment.Split ignored->"Split";case Payment.Free ignored->"Free";};}
    static Data data(String constructor,long a,long b){
        return switch(constructor){
            case "Cash","Leaf"->new Data.Variant(constructor,List.of(number(a)));
            case "Split"->new Data.Variant(constructor,List.of(number(a),number(b)));
            case "Card"->new Data.Variant(constructor,List.of(new Data.Struct(List.of(new Data.Field("name",new Data.Text("Account")),new Data.Field("amount",number(a))))));
            case "Branch"->new Data.Variant(constructor,List.of(data("Leaf",a,0),data("Leaf",b,0)));
            default->new Data.Variant(constructor,List.of());
        };
    }
    static Data model(String name,Data raw,Budget.Limits limits,boolean bypass,String text){
        return switch(name){
            case "Payment"->(text!=null?Payment.read(text,limits):bypass?Payment.fromDataWithoutValidation(raw,limits):Payment.fromData(raw,limits)).rawData();
            case "Paid"->(text!=null?Paid.read(text,limits):bypass?Paid.fromDataWithoutValidation(raw,limits):Paid.fromData(raw,limits)).rawData();
            case "Large"->(text!=null?Large.read(text,limits):bypass?Large.fromDataWithoutValidation(raw,limits):Large.fromData(raw,limits)).rawData();
            case "Bounded"->(text!=null?Bounded.read(text,limits):bypass?Bounded.fromDataWithoutValidation(raw,limits):Bounded.fromData(raw,limits)).rawData();
            case "Ordered"->(text!=null?Ordered.read(text,limits):bypass?Ordered.fromDataWithoutValidation(raw,limits):Ordered.fromData(raw,limits)).rawData();
            case "Unknown"->(text!=null?Unknown.read(text,limits):bypass?Unknown.fromDataWithoutValidation(raw,limits):Unknown.fromData(raw,limits)).rawData();
            case "Tree"->(text!=null?Tree.read(text,limits):bypass?Tree.fromDataWithoutValidation(raw,limits):Tree.fromData(raw,limits)).rawData();
            case "PositiveTree"->(text!=null?PositiveTree.read(text,limits):bypass?PositiveTree.fromDataWithoutValidation(raw,limits):PositiveTree.fromData(raw,limits)).rawData();
            default->throw new AssertionError();
        };
    }
    public static void main(String[] args)throws Exception{
        var input=new BufferedReader(new InputStreamReader(System.in,StandardCharsets.UTF_8));String line;
        while((line=input.readLine())!=null){
            String[] f=line.split("\t",-1);var raw=data(f[2],Long.parseLong(f[3]),Long.parseLong(f[4]));var limits=new Budget.Limits(Long.parseLong(f[5]),Long.parseLong(f[6]));Validation.Outcome outcome;
            try{Data checked=model(f[1],raw,limits,f[0].equals("bypass"),f[0].equals("read")?units(f[7]):null);if(!f[0].equals("read"))require(checked==raw);outcome=new Validation.Valid();}
            catch(ValidationException failure){outcome=failure.outcome();}
            var report=new StringBuilder(outcome.state().name().toLowerCase(Locale.ROOT)).append('|').append(outcome.incomplete());for(var d:outcome.diagnostics())report.append('|').append(hex(d.code())).append(',').append(hex(String.join(";",d.paths()))).append(',').append(hex(d.predicate())).append(',').append(hex(d.message()));System.out.println(report);
        }
        require(Payment.class.isSealed()&&Paid.class.isSealed()&&Payment.Cash.class.isSealed());
        UnionProof.run();
        Paid child=new Large.Cash(amount(100));Payment parent=child;
        require(total(parent).equals(BigInteger.valueOf(100))&&branch(child).equals("Cash"));
        require(parent instanceof Payment.Cash&&child instanceof Paid.Cash);
        require(parent.variant()==parent&&child.variant()==child);
        var unsafe=Large.Cash.createWithoutValidation(amount(1));Payment upcast=unsafe;require(upcast==unsafe);
        require(upcast.validate().state()==Validation.State.INVALID);
        rejects(()->new Paid.Free());require(Paid.Free.createWithoutValidation().validate().state()==Validation.State.INVALID);
        require(new Payment.Free().update(draft->{}).rawData() instanceof Data.Variant);
        rejects(()->new Unknown.Cash(amount(1)));
        require(Unknown.Cash.createWithoutValidation(amount(1)).validate().state()==Validation.State.INDETERMINATE);
        rejects(()->Payment.Cash.fromData(new Data.Variant("Free",List.of())));
        rejects(()->Payment.Cash.fromDataWithoutValidation(new Data.Variant("Free",List.of())));
        rejects(()->Payment.Cash.read("Free"));
        require(Payment.Cash.validateData(new Data.Variant("Free",List.of())).state()==Validation.State.INVALID);
        rejects(()->Payment.fromDataWithoutValidation(new Data.Variant("Cash",List.of(new Data.Text("wrong")))));
        var ordered=new Ordered.Split(amount(1),amount(2));Payment.Split.Draft[] escaped=new Payment.Split.Draft[1];
        var updated=ordered.update(draft->{escaped[0]=draft;draft.setValue1(amount(3));draft.setValue2(amount(4));});
        require(ordered.value1().value().intValueExact()==1&&updated.value1().value().intValueExact()==3);
        escaped[0].setValue2(amount(0));require(updated.value2().value().intValueExact()==4);
        rejects(()->ordered.update(draft->draft.setValue1(amount(5))));
        var invalid=ordered.updateWithoutValidation(draft->draft.setValue1(amount(5)));require(invalid.validate().state()==Validation.State.INVALID);
        rejects(()->Ordered.read(invalid.showWithoutValidation()));
        var identity=ordered.update(draft->{});require(identity.rawData()==ordered.rawData());
        var built=Ordered.Split.create(draft->{escaped[0]=draft;draft.setValue1(null);draft.setValue1(amount(3));draft.setValue2(amount(4));});
        require(built.value1().value().intValueExact()==3&&built.value2().value().intValueExact()==4);
        escaped[0].setValue1(amount(100));require(built.value1().value().intValueExact()==3);
        rejects(()->Ordered.Split.create(draft->draft.setValue1(amount(3))));
        rejects(()->Ordered.Split.create(draft->{draft.setValue1(amount(4));draft.setValue2(amount(3));}));
        rejects(()->Ordered.Split.createWithoutValidation(draft->{}));
        rejects(()->Ordered.Split.create(draft->{draft.setValue1(amount(3));draft.setValue2(amount(4));},new Budget.Limits(1,0)));
        require(Ordered.Split.createWithoutValidation(draft->{draft.setValue1(amount(4));draft.setValue2(amount(3));}).validate().state()==Validation.State.INVALID);
        require(Payment.Free.create(draft->{}).validate().state()==Validation.State.VALID);
        rejects(()->Paid.Free.create(draft->{}));
        try{ordered.update(draft->{draft.setValue1(amount(100));throw new IllegalStateException("callback failure");});throw new AssertionError();}
        catch(IllegalStateException expected){require(expected.getMessage().equals("callback failure"));}
        require(ordered.value1().value().intValueExact()==1);
        var mutable=new java.util.ArrayList<Payment>();mutable.add(new Payment.Free());
        var envelope=new Envelope(new Paid.Cash(amount(1)),mutable,new ModelMaybe.Just<>(new Payment.Free()));mutable.clear();require(envelope.alternatives().size()==1);
        try{envelope.alternatives().clear();throw new AssertionError();}catch(UnsupportedOperationException expected){}
        require(new Token.Token_("value").value().equals("value"));
        require(new Collision.String_(BigInteger.ONE).value().equals(BigInteger.ONE));
        require(new Collision.Draft_(BigInteger.ONE).rawData() instanceof Data.Variant);
        require(new Collision.Data_(true).value());
        require(((Data.Variant)new NameClash.Marker_(BigInteger.ONE).rawData()).name().equals("Marker"));
        require(((Data.Variant)new NameClash.Marker__(BigInteger.ONE).rawData()).name().equals("Marker_"));
        PropertyChecker.customized().withIterationCount(2000).forAll(Generator.integers(),seed->{
            long n=Integer.toUnsignedLong(seed)+1;Paid value=(seed&1)==0?new Paid.Cash(amount(n)):new Paid.Split(amount(n),amount(1));
            require(total(value).signum()>0&&total(Paid.read(value.showWithoutValidation())).equals(total(value)));return true;
        });
        PropertyChecker.customized().withIterationCount(2000).forAll(Generator.integers(),seed->{
            long n=Integer.toUnsignedLong(seed);var before=new Ordered.Split(amount(n),amount(n+1));var after=before.update(draft->{draft.setValue1(amount(n+10));draft.setValue2(amount(n+11));});
            require(after.value1().value().longValueExact()==n+10&&before.value1().value().longValueExact()==n);rejects(()->before.update(draft->draft.setValue1(amount(n+1))));return true;
        });
        PropertyChecker.customized().withIterationCount(2000).forAll(Generator.integers(),seed->{
            int depth=Math.floorMod(seed,25);Tree tree=new Tree.Leaf(BigInteger.ZERO);for(int i=0;i<depth;i++)tree=new Tree.Branch(tree,new Tree.Leaf(BigInteger.valueOf(i)));
            var refined=PositiveTree.fromData(tree.rawData());require(refined instanceof Tree.Leaf||refined instanceof Tree.Branch);require(PositiveTree.read(refined.showWithoutValidation()).validate().state()==Validation.State.VALID);return true;
        });
    }
}
`
