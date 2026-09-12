package java

import (
    "encoding/base64"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/native"
)

func TestAvroBigDecimalApacheOracle(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=avroClasspath(t);dir:=t.TempDir();source:=filepath.Join(dir,"BigDecimalOracle.java");if err:=os.WriteFile(source,[]byte(avroBigDecimalOracleHarness),0600);err!=nil{t.Fatal(err)};classes:=filepath.Join(dir,"classes")
    if output,err:=exec.Command(compiler,"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes,source).CombinedOutput();err!=nil{t.Fatalf("Avro big-decimal oracle javac: %v\n%s",err,output)}
    output,err:=exec.Command(vm,"-Xss256k","-Xmx64m","-cp",classes+string(os.PathListSeparator)+classpath,"BigDecimalOracle").CombinedOutput();if err!=nil{t.Fatalf("Avro big-decimal oracle: %v\n%s",err,output)};lines:=strings.Split(strings.TrimSpace(string(output)),"\n");want:=[][]byte{{8,4,4,0xd2,4},{6,2,0xff,4},{6,2,1,3}};if len(lines)!=len(want){t.Fatalf("oracle produced %d lines for %d values",len(lines),len(want))}
    project,err:=native.IngestProject(native.Avro,[]byte(`{"type":"bytes","logicalType":"big-decimal"}`),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Datum"}});if err!=nil{t.Fatal(err)}
    for i,line:=range lines{datum,err:=base64.StdEncoding.DecodeString(line);if err!=nil{t.Fatal(err)};if string(datum)!=string(want[i]){t.Fatalf("Apache encoding %d: got %v want %v",i,datum,want[i])};if err:=project.ValidateAvroBinary(datum,native.AvroPayloadLimits{});err!=nil{t.Fatalf("native validator rejected Apache encoding %d: %v",i,err)}}
}

const avroBigDecimalOracleHarness=`
import java.io.ByteArrayOutputStream;
import java.math.BigDecimal;
import java.nio.ByteBuffer;
import java.util.Base64;
import org.apache.avro.Conversions;
import org.apache.avro.LogicalTypes;
import org.apache.avro.Schema;
import org.apache.avro.io.EncoderFactory;

public final class BigDecimalOracle {
    private BigDecimalOracle() {}

    public static void main(String[] args) throws Exception {
        var schema = LogicalTypes.bigDecimal().addToSchema(Schema.create(Schema.Type.BYTES));
        var conversion = new Conversions.BigDecimalConversion();
        for (var text : new String[] {"12.34", "-0.01", "1E+2"}) {
            ByteBuffer payload = conversion.toBytes(new BigDecimal(text), schema, schema.getLogicalType());
            var output = new ByteArrayOutputStream();
            var encoder = EncoderFactory.get().binaryEncoder(output, null);
            encoder.writeBytes(payload);
            encoder.flush();
            System.out.println(Base64.getEncoder().encodeToString(output.toByteArray()));
        }
    }
}
`
