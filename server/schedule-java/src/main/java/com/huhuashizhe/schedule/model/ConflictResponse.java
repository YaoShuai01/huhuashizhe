package com.huhuashizhe.schedule.model;

public class ConflictResponse {
    public String error = "conflict";
    public String message;
    public long currentRevision;
    public ScheduleData schedule;
}
