package com.huhuashizhe.schedule.service;

import com.huhuashizhe.schedule.model.Change;

import java.util.List;

public class DiffResult {
    public final List<Change> changes;
    public final List<String> changedMemberIds;

    public DiffResult(List<Change> changes, List<String> changedMemberIds) {
        this.changes = changes;
        this.changedMemberIds = changedMemberIds;
    }
}
