package com.huhuashizhe.schedule.model;

import java.util.List;

public class SubmitResponse {
    public ScheduleData schedule;
    public List<Change> changes;
    public List<String> changedMemberIds;
    public String committedAt;
}
