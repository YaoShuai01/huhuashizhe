package com.huhuashizhe.schedule.service;

import com.huhuashizhe.schedule.model.Member;

import java.util.List;
import java.util.Map;

public class ValidatedPayload {
    public final List<Member> members;
    public final Map<String, String> assignments;
    public final List<String> rotation;
    public final String updatedBy;

    public ValidatedPayload(
            List<Member> members,
            Map<String, String> assignments,
            List<String> rotation,
            String updatedBy) {
        this.members = members;
        this.assignments = assignments;
        this.rotation = rotation;
        this.updatedBy = updatedBy;
    }
}
