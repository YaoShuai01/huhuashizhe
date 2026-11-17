package com.huhuashizhe.schedule.db;

import com.huhuashizhe.schedule.model.Member;
import com.huhuashizhe.schedule.model.ScheduleData;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ScheduleRepositoryTest {

    @TempDir
    Path tempDir;

    @Test
    void initializesSeedWritesWithRevisionLockAndCreatesBackup() throws Exception {
        Path db = tempDir.resolve("schedule.db");
        Path backups = tempDir.resolve("backups");
        ScheduleRepository repository = new ScheduleRepository(db, backups);
        repository.initialize();

        ScheduleRepository.Record seed = repository.read();
        assertEquals(1, seed.revision);
        assertEquals(0, seed.schedule.members.size());

        ScheduleData next = new ScheduleData();
        next.revision = 2;
        next.updatedAt = "2026-11-16T12:00:00Z";
        next.updatedBy = "测试";
        next.members = new ArrayList<>();
        next.members.add(new Member("m_test", "测试", true));
        next.assignments = new LinkedHashMap<>();
        next.assignments.put("2026-11-17", "m_test");

        assertTrue(repository.writeIfRevision(1, next));
        assertEquals(2, repository.read().revision);
        assertTrue(Files.exists(backups.resolve("schedule-r2.json")));
        assertTrue(Files.exists(backups.resolve("schedule-latest.json")));

        // 旧版本再次提交必须失败，防止覆盖
        assertFalse(repository.writeIfRevision(1, next));
    }
}
