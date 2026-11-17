package com.huhuashizhe.schedule.service;

import com.huhuashizhe.schedule.model.Change;
import com.huhuashizhe.schedule.model.ChangeLogEntry;
import com.huhuashizhe.schedule.model.Member;
import com.huhuashizhe.schedule.model.ScheduleData;
import com.huhuashizhe.schedule.model.SubmitRequest;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ScheduleValidatorTest {

    @Test
    void acceptsValidPayloadAndSortsAssignments() {
        SubmitRequest request = new SubmitRequest();
        request.members = new ArrayList<>();
        request.members.add(new Member("m1", " 张三 ", true));
        request.members.add(new Member("m2", "李四", true));
        request.assignments = new LinkedHashMap<>();
        request.assignments.put("2026-11-18", "m2");
        request.assignments.put("2026-11-17", "m1");
        request.updatedBy = "管理员";

        ValidatedPayload payload = ScheduleValidator.validate(request);

        assertEquals(2, payload.members.size());
        assertEquals("张三", payload.members.get(0).name);
        assertEquals("2026-11-17", payload.assignments.keySet().iterator().next());
        assertEquals("管理员", payload.updatedBy);
    }

    @Test
    void rejectsEmptyMembersDuplicateNamesInvalidDateAndUnknownMember() {
        SubmitRequest empty = new SubmitRequest();
        empty.members = new ArrayList<>();
        empty.assignments = new LinkedHashMap<>();
        assertThrows(ValidationException.class, () -> ScheduleValidator.validate(empty));

        SubmitRequest duplicate = new SubmitRequest();
        duplicate.members = new ArrayList<>();
        duplicate.members.add(new Member("m1", "张三", true));
        duplicate.members.add(new Member("m2", " 张三 ", true));
        duplicate.assignments = new LinkedHashMap<>();
        assertThrows(ValidationException.class, () -> ScheduleValidator.validate(duplicate));

        SubmitRequest invalidDate = baseRequest();
        invalidDate.assignments.put("2026-02-30", "m1");
        assertThrows(ValidationException.class, () -> ScheduleValidator.validate(invalidDate));

        SubmitRequest unknownMember = baseRequest();
        unknownMember.assignments.put("2026-11-17", "missing");
        assertThrows(ValidationException.class, () -> ScheduleValidator.validate(unknownMember));
    }

    @Test
    void diffReturnsChangesAndAffectedMembers() {
        Map<String, String> oldAssignments = new LinkedHashMap<>();
        oldAssignments.put("2026-11-17", "m1");
        oldAssignments.put("2026-11-18", "m2");

        Map<String, String> newAssignments = new LinkedHashMap<>();
        newAssignments.put("2026-11-17", "m2");
        newAssignments.put("2026-11-19", "m1");

        DiffResult result = ScheduleValidator.diff(oldAssignments, newAssignments);

        assertEquals(3, result.changes.size());
        assertEquals("2026-11-17", result.changes.get(0).date);
        assertEquals("m1", result.changes.get(0).from);
        assertEquals("m2", result.changes.get(0).to);
        assertTrue(result.changedMemberIds.contains("m1"));
        assertTrue(result.changedMemberIds.contains("m2"));
    }

    @Test
    void buildNextIncrementsRevisionAndAppendsChangeLog() {
        ScheduleData current = new ScheduleData();
        current.revision = 3;
        current.members = new ArrayList<>();
        current.members.add(new Member("m1", "张三", true));
        current.members.add(new Member("m2", "李四", true));
        current.assignments = new LinkedHashMap<>();
        current.assignments.put("2026-11-17", "m1");
        current.changeLog = new ArrayList<>();

        ValidatedPayload payload = new ValidatedPayload(
                current.members,
                new LinkedHashMap<>(Map.of("2026-11-17", "m2")),
                null,
                "管理员");

        BuildResult result = ScheduleValidator.buildNext(
                current,
                payload,
                Instant.parse("2026-11-16T12:00:00Z"));

        assertEquals(4, result.schedule.revision);
        assertEquals("2026-11-16T12:00:00Z", result.schedule.updatedAt);
        assertEquals("管理员", result.schedule.updatedBy);
        assertEquals(1, result.schedule.changeLog.size());
        ChangeLogEntry entry = result.schedule.changeLog.get(0);
        assertEquals("2026-11-17", entry.changes.get(0).date);
        assertEquals("m1", entry.changes.get(0).from);
        assertEquals("m2", entry.changes.get(0).to);
        assertEquals(1, result.diff.changes.size());
    }

    @Test
    void validatesAndPreservesRotationSequence() {
        SubmitRequest request = baseRequest();
        request.rotation = Arrays.asList("m2", "m1", "m2");
        ValidatedPayload payload = ScheduleValidator.validate(request);
        assertEquals(Arrays.asList("m2", "m1", "m2"), payload.rotation);

        request.rotation = null;
        assertNull(ScheduleValidator.validate(request).rotation);

        request.rotation = Collections.singletonList("missing");
        assertThrows(ValidationException.class, () -> ScheduleValidator.validate(request));
    }

    private SubmitRequest baseRequest() {
        SubmitRequest request = new SubmitRequest();
        request.members = new ArrayList<Member>();
        request.members.add(new Member("m1", "张三", true));
        request.members.add(new Member("m2", "李四", true));
        request.assignments = new LinkedHashMap<>();
        request.assignments.put("2026-11-17", "m1");
        request.updatedBy = "管理员";
        return request;
    }
}
