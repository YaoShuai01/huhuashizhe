package com.huhuashizhe.schedule.model;

import java.util.ArrayList;
import java.util.List;

public class ChangeLogEntry {
    public String at;
    public String by;
    public List<Change> changes = new ArrayList<>();
    public Boolean truncated;

    public ChangeLogEntry() {
    }
}
