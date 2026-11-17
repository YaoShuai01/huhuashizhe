package com.huhuashizhe.schedule.service;

import com.huhuashizhe.schedule.model.ScheduleData;

public class BuildResult {
    public final ScheduleData schedule;
    public final DiffResult diff;

    public BuildResult(ScheduleData schedule, DiffResult diff) {
        this.schedule = schedule;
        this.diff = diff;
    }
}
