package java

import (
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

const modelContract = `
positive :: Int -> Bool
positive n = n > 0
type FunctionAge = Int where positive it
guarded :: (Int where it > 0) -> Bool
guarded _ = True
type GuardedAge = Int where guarded it
acceptAge :: Age -> Bool
acceptAge _ = True
type ReadAge = String where (case read it of { Ok age -> acceptAge age; Err _ -> False })
type AccountId = String
type OtherId = String
type Age = Int where it >= 0 @code "age.nonnegative"
type AdultAge = Age where it >= 18 @code "age.adult"
type ElderAge = AdultAge where it >= 65
type Booking = { checkIn :: Int, checkOut :: Int }
  where it.checkIn < it.checkOut @code "booking.order"
type FutureBooking = Booking where it.checkIn >= 0
type User = { id :: AccountId, age :: Age, active :: Bool,
  nickname :: Maybe String, alias :: Nullable String, children :: [Age] }
type Node = { value :: Int, next :: Maybe Node }
type Matrix = [[Int]]
type Answer = Result String Age
type Small = UInt8
type PrimitiveFields = { count :: Int where it > 0, ratio :: Real where it >= 0.0 }
type Collision = { class :: Int, class_ :: Int, x :: Int, X :: Int, rawData :: Int }
type Uncertain = Real where it / 0.0 > 0.0
type Empty = {}
type OptionalAge = Maybe Age
type OptionalRefinement = Maybe (Int where it > 0)
type CodecCollision = { read :: String, showWithoutValidation :: String }
`

func TestGeneratedSemanticModels(t *testing.T){
    compiler,vm:=javaTools(t);dependencies:=jetCheckClasspath(t)
    program,err:=language.Compile(modelContract);if err!=nil{t.Fatal(err)}
    files,err:=GenerateModels(program,"example.models","Contract");if err!=nil{t.Fatal(err)}
    dir:=t.TempDir();sources:=[]string{}
    for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    proof:=filepath.Join(dir,"example","models","ProofChecks.java")
    proofSource:=`package example.models;
public final class ProofChecks {
    public static void run() {
        var wrong = ModelSupport.validate("OtherId", new Data.Text("x"), Budget.Limits.defaults());
        try { new AccountId(wrong); throw new AssertionError("foreign nominal evidence accepted"); } catch (IllegalArgumentException expected) {}
        var child = ModelSupport.validate("ElderAge", new Data.Number(Rational.of(65)), Budget.Limits.defaults());
        if (!new Age(child).value().equals(java.math.BigInteger.valueOf(65))) throw new AssertionError("parent evidence rejected");
    }
}`
    if err:=os.WriteFile(proof,[]byte(proofSource),0644);err!=nil{t.Fatal(err)};sources=append(sources,proof)
    candidate:=testRecord(value.DataField{Name:"checkIn",Value:testNumber("3")},value.DataField{Name:"checkOut",Value:testNumber("4")})
    minimum:=uint64(0);for limit:=uint64(1);limit<1000;limit++{if validation.StateName(program.ValidateData("Booking",candidate,validation.Limits{Total:limit}).State())=="valid"{minimum=limit;break}}
    if minimum==0{t.Fatal("no valid Go booking budget")}
    harnessSource:=strings.ReplaceAll(modelHarnessJava,"@BOOKING_BUDGET@",fmt.Sprint(minimum))
    harness:=filepath.Join(dir,"Models.java");if err:=os.WriteFile(harness,[]byte(harnessSource),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness)
    classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",dependencies,"-d",classes},sources...)
    if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("javac models: %v\n%s",err,output)}
    ctx,cancel:=context.WithTimeout(context.Background(),time.Minute);defer cancel()
    if output,err:=exec.CommandContext(ctx,vm,"-cp",classes+string(os.PathListSeparator)+dependencies,"Models").CombinedOutput();err!=nil{t.Fatalf("Java models: %v\n%s",err,output)}else{t.Log(string(output))}
    // An unrelated nominal wrapper with the same base type must not substitute.
    negative:=filepath.Join(dir,"Wrong.java");if err:=os.WriteFile(negative,[]byte(`import example.models.*; class Wrong { AccountId id = new OtherId("x"); }`),0644);err!=nil{t.Fatal(err)}
    if output,err:=exec.Command(compiler,"--release","25","-cp",classes,negative).CombinedOutput();err==nil||!strings.Contains(string(output),"incompatible types"){t.Fatalf("unrelated nominal types became interchangeable: %v %s",err,output)}
}

const modelHarnessJava = `
import example.models.*;
import java.math.BigInteger;
import java.util.List;
import java.util.ArrayList;
import org.jetbrains.jetCheck.Generator;
import org.jetbrains.jetCheck.PropertyChecker;

public final class Models {
    static BigInteger n(long value) { return BigInteger.valueOf(value); }
    static Data raw(long value) { return new Data.Number(Rational.of(value)); }
    static void require(boolean condition) { if (!condition) throw new AssertionError("model law failed"); }
    static void rejects(Runnable action) {
        try { action.run(); throw new AssertionError("invalid construction succeeded"); }
        catch (ValidationException expected) {}
    }
    static BigInteger parentValue(Age parent) { return parent.value(); }
    record Range(int start, int span) {}
    public static void main(String[] args) {
        require(new FunctionAge(n(1)).value().equals(n(1)));
        rejects(() -> new FunctionAge(n(0)));
        require(FunctionAge.createWithoutValidation(n(-1)).validate().state() == Validation.State.INVALID);
        require(new GuardedAge(n(1)).value().equals(n(1)));
        rejects(() -> new GuardedAge(n(0)));
        require(GuardedAge.createWithoutValidation(n(-1)).validate().state() == Validation.State.INDETERMINATE);
        require(Contract.showWithoutValidation(GuardedAge.createWithoutValidation(n(-1)).rawData()).equals("-1"));
        require(new ReadAge("21").value().equals("21"));
        rejects(() -> new ReadAge("-1")); rejects(() -> new ReadAge("not a number"));
        require(Age.fromData(Contract.read("Age", "21").orThrow()).value().equals(n(21)));
        require(Contract.read("Age", Contract.showWithoutValidation(Age.createWithoutValidation(n(-1)).rawData())).data() == null);
        Age readParent = ElderAge.read("65"); require(readParent.value().equals(n(65)));
        require(Age.read("21").showWithoutValidation().equals("21"));
        rejects(() -> AdultAge.read("17")); rejects(() -> Age.read("1", new Budget.Limits(1,0)));
        rejects(() -> Age.read(Age.createWithoutValidation(n(-1)).showWithoutValidation()));
        var codecCollision = CodecCollision.read("{read = \"x\", showWithoutValidation = \"y\"}");
        require(codecCollision.read_().equals("x") && codecCollision.showWithoutValidation_().equals("y"));
        ProofChecks.run();
        String spelling = new String(new char[]{'x', (char)0xd800}); AccountId id = new AccountId(spelling);
        require(id.value() == spelling);
        Age age = new Age(n(21)); AdultAge adult = new AdultAge(n(21)); ElderAge elder = new ElderAge(n(65));
        require(parentValue(adult).equals(n(21))); require(parentValue(elder).equals(n(65)));
        require(((Age)adult).rawData() == adult.rawData());
        rejects(() -> new Age(n(-1))); rejects(() -> new AdultAge(n(17)));
        Age unsafe = Age.createWithoutValidation(n(-1)); require(unsafe.value().equals(n(-1)));
        require(unsafe.validate().state() == Validation.State.INVALID);
        // Parent substitution/access must not revalidate even an explicit unsafe value.
        require(parentValue(AdultAge.createWithoutValidation(n(-1))).equals(n(-1)));
        rejects(() -> Small.fromDataWithoutValidation(raw(256)));
        rejects(() -> Age.fromDataWithoutValidation(new Data.Number(Rational.parse("1/3"))));
        rejects(() -> Age.fromDataWithoutValidation(new Data.Text("bad")));
        rejects(() -> new AccountId(null));
        require(AccountId.validateData(null).state() == Validation.State.INVALID);
        require(Contract.validate(null, raw(1)).state() == Validation.State.INVALID);
        rejects(() -> new Uncertain(Rational.ONE));
        require(Uncertain.createWithoutValidation(Rational.ONE).validate().state() == Validation.State.INDETERMINATE);
        require(new Empty().validate().state() == Validation.State.VALID);
        require(new Empty().update(draft -> {}).validate().state() == Validation.State.VALID);
        require(new OptionalAge(new ModelMaybe.Just<>(age)).value() instanceof ModelMaybe.Just<?>);
        rejects(() -> new OptionalRefinement(new ModelMaybe.Just<>(n(-1))));
        require(OptionalRefinement.createWithoutValidation(new ModelMaybe.Just<>(n(-1))).validate().state() == Validation.State.INVALID);
        rejects(() -> new PrimitiveFields(n(0), Rational.ZERO));
        PrimitiveFields bypass = PrimitiveFields.createWithoutValidation(n(0), Rational.ZERO);
        require(bypass.count().equals(n(0))); require(bypass.ratio().equals(Rational.ZERO));

        Booking original = new Booking(n(1), n(2));
        final Booking.Draft[] escaped = new Booking.Draft[1];
        Booking changed = original.update(draft -> { escaped[0] = draft; draft.setCheckIn(n(3)); draft.setCheckOut(n(4)); });
        require(original.checkIn().equals(n(1))); require(changed.checkIn().equals(n(3)));
        Booking tight = original.update(draft -> { draft.setCheckIn(n(3)); draft.setCheckOut(n(4)); }, new Budget.Limits(@BOOKING_BUDGET@,0));
        require(tight.checkIn().equals(n(3)));
        rejects(() -> original.update(draft -> { draft.setCheckIn(n(3)); draft.setCheckOut(n(4)); }, new Budget.Limits(@BOOKING_BUDGET@ - 1,0)));
        Booking interimNull = original.update(draft -> { draft.setCheckIn(null); draft.setCheckIn(n(3)); draft.setCheckOut(n(4)); });
        require(interimNull.checkIn().equals(n(3)));
        escaped[0].setCheckIn(n(100)); escaped[0].setCheckOut(n(-1)); require(changed.checkOut().equals(n(4)));
        rejects(() -> original.update(draft -> draft.setCheckIn(n(10)))); require(original.checkIn().equals(n(1)));
        try { original.update(draft -> { draft.setCheckIn(n(100)); throw new IllegalStateException("caller failure"); }); throw new AssertionError("callback exception swallowed"); }
        catch (IllegalStateException expected) { require(expected.getMessage().equals("caller failure")); }
        require(original.checkIn().equals(n(1)));
        Booking invalid = original.updateWithoutValidation(draft -> draft.setCheckIn(n(10)));
        require(invalid.validate().state() == Validation.State.INVALID);
        rejects(() -> original.update(draft -> {}, new Budget.Limits(1, 1)));
        FutureBooking future = new FutureBooking(n(1), n(2));
        FutureBooking later = future.update(draft -> { draft.setCheckIn(n(5)); draft.setCheckOut(n(6)); });
        require(later.checkIn().equals(n(5))); rejects(() -> future.update(draft -> draft.setCheckIn(n(-1))));
        Booking asParent = future; rejects(() -> asParent.update(draft -> draft.setCheckIn(n(-1))));

        var mutable = new ArrayList<Age>(); mutable.add(age);
        User user = new User(id, adult, true, new ModelMaybe.Nothing<>(), new ModelNullable.Null<>(), mutable);
        mutable.clear(); require(user.children().size() == 1); require(user.age().value().equals(n(21)));
        require(user.id().value().equals(spelling)); require(user.nickname() instanceof ModelMaybe.Nothing<?>);
        require(user.alias() instanceof ModelNullable.Null<?>);
        var rawFields = new ArrayList<Data.Field>(); for (var field : ((Data.Struct)user.rawData()).fields()) if (!field.name().equals("nickname")) rawFields.add(field);
        rawFields.add(new Data.Field("future", new Data.Text("untouched")));
        Data withAbsentAndExtra = new Data.Struct(rawFields); User imported = User.fromData(withAbsentAndExtra);
        require(imported.nickname() instanceof ModelMaybe.Nothing<?>);
        require(imported.update(draft -> {}).rawData() == withAbsentAndExtra);
        User updated = imported.update(draft -> draft.setAge(new Age(n(30))));
        require(((Data.Struct)updated.rawData()).fields().stream().noneMatch(f -> f.name().equals("nickname")));
        require(((Data.Struct)updated.rawData()).fields().getLast().name().equals("future"));
        User added = imported.update(draft -> draft.setNickname(new ModelMaybe.Just<>("present")));
        require(((ModelMaybe.Just<String>)added.nickname()).value().equals("present"));
        try { user.children().clear(); throw new AssertionError("mutable collection"); } catch (UnsupportedOperationException expected) {}
        rejects(() -> new User(id, unsafe, true, new ModelMaybe.Nothing<>(), new ModelNullable.Null<>(), List.of()));
        var inner = new ArrayList<BigInteger>(); inner.add(n(1)); var rows = new ArrayList<List<BigInteger>>(); rows.add(inner);
        Matrix matrix = new Matrix(rows); inner.clear(); rows.clear(); require(matrix.value().getFirst().equals(List.of(n(1))));
        try { matrix.value().getFirst().clear(); throw new AssertionError("mutable nested collection"); } catch (UnsupportedOperationException expected) {}
        Node tail = new Node(n(2), new ModelMaybe.Nothing<>()); Node head = new Node(n(1), new ModelMaybe.Just<>(tail));
        require(head.value().equals(n(1))); require(((ModelMaybe.Just<Node>)head.next()).value().value().equals(n(2)));
        Answer answer = new Answer(new ModelResult.Ok<String, Age>(age));
        require(((ModelResult.Ok<String, Age>)answer.value()).value().value().equals(n(21)));
        Collision collision = new Collision(n(1), n(2), n(3), n(4), n(5));
        require(collision.class_().equals(n(1))); require(collision.class__().equals(n(2))); require(collision.rawData_().equals(n(5)));
        Collision renamed = collision.update(draft -> { draft.setX(n(6)); draft.setX_(n(7)); });
        require(renamed.x().equals(n(6))); require(renamed.X().equals(n(7)));

        PropertyChecker.customized().withIterationCount(2000).forAll(Generator.integers(), value -> {
            if (value >= 0) require(new Age(n(value)).value().equals(n(value)));
            else rejects(() -> new Age(n(value)));
            require(Age.createWithoutValidation(n(value)).value().equals(n(value)));
            return true;
        });
        PropertyChecker.customized().withIterationCount(2000).forAll(
            Generator.zipWith(Generator.integers(-1000000, 1000000), Generator.integers(1, 1000), Range::new), range -> {
                Booking before = new Booking(n(range.start()), n((long)range.start() + range.span()));
                Booking after = before.update(draft -> { draft.setCheckIn(n((long)range.start() + 2000)); draft.setCheckOut(n((long)range.start() + range.span() + 2000)); });
                require(before.checkIn().equals(n(range.start()))); require(after.checkOut().subtract(after.checkIn()).equals(n(range.span())));
                return true;
            });
        System.out.println("semantic models: constructors, nominal inheritance, bypasses, immutable atomic updates and 4000 jetCheck cases passed");
    }
}
`

func TestModelGenerationBoundaries(t *testing.T){
    nested,err:=language.Compile("type Nested = { value :: { inner :: Int } }");if err!=nil{t.Fatal(err)};nestedFiles,err:=GenerateModels(nested,"example","Contract");if err!=nil{t.Fatal(err)};foundParent,foundChild:=false,false;for _,file:=range nestedFiles{if strings.HasSuffix(file.Path,"/Nested.java"){foundParent=strings.Contains(file.Source,"NestedValueRecord value()")};if strings.HasSuffix(file.Path,"/NestedValueRecord.java"){foundChild=strings.Contains(file.Source,"class NestedValueRecord")&&strings.Contains(file.Source,"BigInteger inner()")}};if !foundParent||!foundChild{t.Fatal("nested anonymous record models were not generated with typed accessors")}
    for _,source:=range []string{"type Unsupported = { callback :: Int -> Int }", "type Contract = Int", "type ModelSupport = Int", "type ModelType = Int", "type Id = Int\ntype ID = Int", "type DATA = Int", "type FooΣ = Int\ntype Fooς = Int"}{
        program,err:=language.Compile(source);if err!=nil{t.Fatal(err)}
        files,err:=GenerateModels(program,"example","Contract");if _,ok:=err.(*GenerationError);!ok||files!=nil{t.Fatalf("unsupported model did not fail atomically: %s: %v",source,err)}
    }
    if files,err:=GenerateModels(nil,"","Contract");files!=nil||err==nil{t.Fatal("nil program accepted")}
    program,err:=language.Compile(modelContract);if err!=nil{t.Fatal(err)}
    first,err:=GenerateModels(program,"example.models","Contract");if err!=nil{t.Fatal(err)}
    copy:=program.Syntax();copy.Types[0].Name="Changed"
    second,err:=GenerateModels(program,"example.models","Contract");if err!=nil{t.Fatal(err)}
    if len(first)!=len(second){t.Fatal("unstable file count")};seen:=map[string]bool{}
    for i,file:=range first{if file!=second[i]||seen[file.Path]{t.Fatal("nondeterministic or colliding output")};seen[file.Path]=true}
}

func TestModelPackageLayouts(t *testing.T){
    compiler,_:=javaTools(t);program,err:=language.Compile("type Id = String\ntype Draft = { label :: String }\ntype Draft_ = Int\ntype Item = { id :: Id, tags :: [String], draftValue :: Draft, other :: Draft_ }\ntype Child = Item\ntype Empty = {}\ntype Variant = Int\ndata Choice = A | B Id | C Variant | Draft__ Draft\ntype SubChoice = Choice\ntype Generic a b = { read :: a, nested :: [Maybe b] }\ntype UsesGeneric = { value :: Generic Id Int }\ntype Derived a b = Generic b [a]");if err!=nil{t.Fatal(err)}
    for _,namespace:=range []string{"", "δοκιμή.映像", "record.var"}{t.Run(namespace,func(t *testing.T){
        files,err:=GenerateModels(program,namespace,"Contract");if err!=nil{t.Fatal(err)}
        dir:=t.TempDir();sources:=[]string{}
        for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
        args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-d",filepath.Join(dir,"classes")},sources...)
        if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("model package: %v %s",err,output)}
    })}
}

func FuzzModelGeneration(f *testing.F){
    f.Add(genericUnionContract)
    f.Add(genericInheritanceContract)
    f.Add(inlineModelContract)
    f.Add(genericModelContract)
    f.Add("type Identity a = a\ntype Box a = { value :: a, next :: Maybe (Box a) }")
    for _,source:=range []string{unionModelContract,"data Draft = A | B Int\ntype Item = { create :: Draft, newDraft :: Int }","data Choice = A | B Int\ntype SubChoice = Choice","data Node = Nil | Cons Int Node","type Id = String", "type Parent = { start :: Int, end :: Int } where it.start < it.end\ntype Child = Parent", "type Node = { value :: Int, next :: Maybe Node }", "type T = [[Int]]", "type T = { class :: Int, class_ :: Int }"}{f.Add(source)}
    f.Fuzz(func(t *testing.T,source string){
        if len(source)>8192{return};program,err:=language.Compile(source);if err!=nil{return}
        first,err:=GenerateModels(program,"example","Contract");second,again:=GenerateModels(program,"example","Contract")
        if err!=nil{if again==nil||first!=nil||second!=nil{t.Fatal("partial or nondeterministic failed model generation")};return}
        if again!=nil||len(first)!=len(second){t.Fatal("unstable model source set")};seen:=map[string]bool{}
        for i,file:=range first{if file!=second[i]||seen[file.Path]{t.Fatal("nondeterministic or colliding model source")};seen[file.Path]=true}
    })
}

func BenchmarkGenerateModels(b *testing.B){
    program,err:=language.Compile(modelContract);if err!=nil{b.Fatal(err)};b.ReportAllocs();b.ResetTimer()
    for i:=0;i<b.N;i++{if _,err:=GenerateModels(program,"example","Contract");err!=nil{b.Fatal(err)}}
}
