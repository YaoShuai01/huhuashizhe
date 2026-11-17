package com.huhuashizhe.schedule.service;

import com.huhuashizhe.schedule.model.Change;
import com.huhuashizhe.schedule.model.ChangeLogEntry;
import com.huhuashizhe.schedule.model.Member;
import com.huhuashizhe.schedule.model.ScheduleData;
import com.huhuashizhe.schedule.model.SubmitRequest;

import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;

public final class ScheduleValidator {
    public static final int MAX_MEMBERS = 200;
    public static final int MAX_ASSIGNMENTS = 5000;
    public static final int MAX_NAME_LENGTH = 30;
    public static final int MAX_CHANGE_LOG = 50;
    public static final int MAX_CHANGES_PER_ENTRY = 100;

    private ScheduleValidator() {
    }

    public static ValidatedPayload validate(SubmitRequest request) {
        if (request == null) {
            throw new ValidationException("轮协内容格式错误");
        }
        if (request.members == null || request.members.isEmpty()) {
            throw new ValidationException("轮协表至少需要一个成员");
        }
        if (request.members.size() > MAX_MEMBERS) {
            throw new ValidationException("成员数量不能超过 " + MAX_MEMBERS + " 人");
        }

        List<Member> members = new ArrayList<>();
        Set<String> ids = new LinkedHashSet<>();
        Set<String> names = new LinkedHashSet<>();
        Set<Integer> usedSeq = new LinkedHashSet<>();
        Map<String, String> idLookup = new HashMap<>();
        Map<String, Boolean> activeLookup = new HashMap<>();
        int nextSeq = 1;

        for (Member raw : request.members) {
            if (raw == null) {
                throw new ValidationException("成员数据格式错误");
            }
            String id = trim(raw.id);
            String name = trim(raw.name);
            if (id.isEmpty() || id.length() > 64) {
                throw new ValidationException("成员 ID 不能为空");
            }
            if (name.isEmpty() || name.length() > MAX_NAME_LENGTH) {
                throw new ValidationException("成员姓名不能为空且不能超过 " + MAX_NAME_LENGTH + " 个字");
            }
            String idKey = id.toLowerCase(Locale.ROOT);
            String nameKey = name.toLowerCase(Locale.ROOT);
            if (ids.contains(idKey)) {
                throw new ValidationException("成员 ID 重复：" + id);
            }
            if (names.contains(nameKey)) {
                throw new ValidationException("成员姓名重复：" + name);
            }
            ids.add(idKey);
            names.add(nameKey);
            boolean active = raw.active == null || raw.active;
            Integer seq = raw.seq;
            if (seq == null || seq <= 0 || !usedSeq.add(seq)) {
                while (usedSeq.contains(nextSeq)) {
                    nextSeq++;
                }
                seq = nextSeq;
                usedSeq.add(seq);
            }
            Member member = new Member(id, name, active, seq);
            // 验证状态由服务端维护，客户端提交的值一律忽略
            member.verified = Boolean.FALSE;
            member.verifiedAt = null;
            members.add(member);
            idLookup.put(idKey, id);
            activeLookup.put(idKey, active);
        }

        if (request.assignments == null) {
            throw new ValidationException("轮协日期数据格式错误");
        }
        if (request.assignments.size() > MAX_ASSIGNMENTS) {
            throw new ValidationException("轮协日期不能超过 " + MAX_ASSIGNMENTS + " 天");
        }

        Map<String, String> assignments = new TreeMap<>();
        for (Map.Entry<String, String> entry : request.assignments.entrySet()) {
            String date = trim(entry.getKey());
            if (!isValidDate(date)) {
                throw new ValidationException("日期格式错误：" + date);
            }
            String memberId = trim(entry.getValue());
            if (memberId.isEmpty()) {
                throw new ValidationException(date + " 的负责人为空");
            }
            String idKey = memberId.toLowerCase(Locale.ROOT);
            String actualId = idLookup.get(idKey);
            if (actualId == null) {
                throw new ValidationException(date + " 的负责人不存在或已停用");
            }
            if (!Boolean.TRUE.equals(activeLookup.get(idKey))) {
                throw new ValidationException(date + " 的负责人不存在或已停用");
            }
            assignments.put(date, actualId);
        }

        List<String> rotation = null;
        if (request.rotation != null) {
            if (request.rotation.size() > MAX_MEMBERS) {
                throw new ValidationException("顺延序列不能超过 " + MAX_MEMBERS + " 人");
            }
            rotation = new ArrayList<>();
            for (String rawId : request.rotation) {
                String memberId = trim(rawId);
                if (memberId.isEmpty()) {
                    continue;
                }
                String idKey = memberId.toLowerCase(Locale.ROOT);
                String actualId = idLookup.get(idKey);
                if (actualId == null || !Boolean.TRUE.equals(activeLookup.get(idKey))) {
                    throw new ValidationException("顺延序列中的成员不存在或已停用：" + memberId);
                }
                // 允许同一个成员在一个周期内出现多次，表示这个周期内值多次班
                rotation.add(actualId);
            }
        }

        String updatedBy = trim(request.updatedBy);
        if (updatedBy.isEmpty()) {
            updatedBy = "admin";
        }
        if (updatedBy.length() > MAX_NAME_LENGTH) {
            updatedBy = updatedBy.substring(0, MAX_NAME_LENGTH);
        }

        return new ValidatedPayload(members, assignments, rotation, updatedBy);
    }

    public static DiffResult diff(
            Map<String, String> oldAssignments,
            Map<String, String> newAssignments) {
        Map<String, String> oldMap = oldAssignments == null ? new HashMap<>() : oldAssignments;
        Map<String, String> newMap = newAssignments == null ? new HashMap<>() : newAssignments;
        Set<String> dates = new TreeSet<>();
        dates.addAll(oldMap.keySet());
        dates.addAll(newMap.keySet());

        List<Change> changes = new ArrayList<>();
        Set<String> memberIds = new LinkedHashSet<>();
        for (String date : dates) {
            String from = oldMap.get(date);
            String to = newMap.get(date);
            if (Objects.equals(from, to)) {
                continue;
            }
            changes.add(new Change(date, from, to));
            if (from != null) {
                memberIds.add(from);
            }
            if (to != null) {
                memberIds.add(to);
            }
        }
        return new DiffResult(changes, new ArrayList<>(memberIds));
    }

    public static BuildResult buildNext(
            ScheduleData current,
            ValidatedPayload payload,
            Instant now) {
        DiffResult diff = diff(current.assignments, payload.assignments);
        String at = now.toString();

        ChangeLogEntry entry = new ChangeLogEntry();
        entry.at = at;
        entry.by = payload.updatedBy;
        entry.changes = new ArrayList<>(
                diff.changes.subList(0, Math.min(MAX_CHANGES_PER_ENTRY, diff.changes.size())));
        if (diff.changes.size() > MAX_CHANGES_PER_ENTRY) {
            entry.truncated = Boolean.TRUE;
        }

        List<ChangeLogEntry> changeLog = new ArrayList<>();
        changeLog.add(entry);
        if (current.changeLog != null) {
            changeLog.addAll(current.changeLog);
        }
        if (changeLog.size() > MAX_CHANGE_LOG) {
            changeLog = new ArrayList<>(changeLog.subList(0, MAX_CHANGE_LOG));
        }

        ScheduleData next = new ScheduleData();
        next.schemaVersion = 1;
        next.revision = current.revision + 1;
        next.updatedAt = at;
        next.updatedBy = payload.updatedBy;
        next.members = payload.members;
        next.assignments = payload.assignments;
        next.rotation = payload.rotation != null ? payload.rotation : current.rotation;
        if (next.rotation == null) {
            next.rotation = new ArrayList<>();
        }
        next.changeLog = changeLog;

        return new BuildResult(next, diff);
    }

    private static boolean isValidDate(String value) {
        if (value == null || value.length() != 10) {
            return false;
        }
        try {
            LocalDate date = LocalDate.parse(value, DateTimeFormatter.ISO_LOCAL_DATE);
            int year = date.getYear();
            return year >= 2000 && year <= 2100;
        } catch (DateTimeParseException e) {
            return false;
        }
    }

    private static String trim(String value) {
        return value == null ? "" : value.trim();
    }
}
