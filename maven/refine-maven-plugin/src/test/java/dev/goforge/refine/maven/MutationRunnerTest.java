package dev.goforge.refine.maven;

import static org.junit.jupiter.api.Assertions.*;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class MutationRunnerTest {
    @TempDir Path directory;

    @Test void successfulProcessWithoutPropertyExecutionIsNotPassingEvidence() throws Exception {
        Path log = directory.resolve("properties.log");
        Files.writeString(log, "BUILD SUCCESS\n");
        assertEquals("infrastructure_error", MutationRunner.propertyOutcome(0, log, 2));
        Files.writeString(log, "REFINE_SUITE PASS properties=1 cases=100 examples=0 suite=One\n");
        assertEquals("infrastructure_error", MutationRunner.propertyOutcome(0, log, 2));
        Files.writeString(log, Files.readString(log).repeat(2));
        assertEquals("infrastructure_error", MutationRunner.propertyOutcome(0, log, 2));
        Files.writeString(log, "REFINE_SUITE PASS properties=1 cases=0 examples=0 suite=One\n");
        assertEquals("infrastructure_error", MutationRunner.propertyOutcome(0, log, 1));
    }
    @Test void crashWithoutPropertyFailureIsNotAKill() throws Exception {
        Path log = directory.resolve("properties.log");
        Files.writeString(log, "Error: Could not find or load main class example.Tests\n");
        assertEquals("infrastructure_error", MutationRunner.propertyOutcome(1, log, 1));
        Files.writeString(log, "REFINE_PROPERTY FAIL valid Example evaluations=12 suite=One\n");
        assertEquals("killed", MutationRunner.propertyOutcome(1, log, 1));
        assertEquals("timeout", MutationRunner.propertyOutcome(124, log, 1));
    }
    @Test void junitRequiresXmlEvidenceAndAllControlTests() throws Exception {
        Files.writeString(directory.resolve("TEST-Example.xml"),
            "<testsuite tests=\"2\" failures=\"1\" errors=\"0\"/>");
        int[] evidence = MutationRunner.junitEvidence(directory);
        assertEquals("killed", MutationRunner.applicationOutcome(1, evidence, 2));
        assertEquals("timeout", MutationRunner.applicationOutcome(124, evidence, 2));
        Files.writeString(directory.resolve("TEST-Example.xml"),
            "<testsuite tests=\"1\" failures=\"0\" errors=\"0\"/>");
        assertEquals("infrastructure_error", MutationRunner.applicationOutcome(0,
            MutationRunner.junitEvidence(directory), 2));
        Files.writeString(directory.resolve("TEST-Example.xml"),
            "<testsuite tests=\"2\" failures=\"0\" errors=\"0\" skipped=\"2\"/>");
        assertEquals("infrastructure_error", MutationRunner.applicationOutcome(0,
            MutationRunner.junitEvidence(directory), 2));
        Files.delete(directory.resolve("TEST-Example.xml"));
        assertEquals("infrastructure_error", MutationRunner.applicationOutcome(1,
            MutationRunner.junitEvidence(directory), 2));
    }
}
