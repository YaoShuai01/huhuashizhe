package com.huhuashizhe.schedule.model;

import java.util.List;
import java.util.Map;

public class SubmitRequest {
    public Long baseRevision;
    public List<Member> members;
    public Map<String, String> assignments;
    public List<String> rotation;
    public String updatedBy;
}
