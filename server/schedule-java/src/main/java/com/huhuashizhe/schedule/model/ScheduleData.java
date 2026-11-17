package com.huhuashizhe.schedule.model;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public class ScheduleData {
    public int schemaVersion = 1;
    public long revision;
    public String updatedAt;
    public String updatedBy;
    public List<Member> members = new ArrayList<>();
    public Map<String, String> assignments = new LinkedHashMap<>();
    public List<String> rotation = new ArrayList<>();
    public List<ChangeLogEntry> changeLog = new ArrayList<>();

    public ScheduleData() {
    }

    public static ScheduleData seed() {
        ScheduleData data = new ScheduleData();
        data.schemaVersion = 1;
        data.revision = 1;
        data.updatedAt = Instant.now().toString();
        data.updatedBy = "system";
        return data;
    }
}
