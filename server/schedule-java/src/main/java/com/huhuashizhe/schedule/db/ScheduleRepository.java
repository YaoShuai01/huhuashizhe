package com.huhuashizhe.schedule.db;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.huhuashizhe.schedule.model.Member;
import com.huhuashizhe.schedule.model.ScheduleData;
import com.huhuashizhe.schedule.web.Json;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * SQLite 持久化：
 * - schedule 表只保留一行（id=1），payload 是完整 JSON
 * - revision 是乐观锁版本号
 * - 每次提交成功后导出 JSON 备份，方便同步到私有仓库
 */
public class ScheduleRepository {
    private static final Logger LOG = Logger.getLogger(ScheduleRepository.class.getName());

    private final Path dbPath;
    private final Path backupDir;
    private final ObjectMapper mapper = Json.mapper();

    public ScheduleRepository(Path dbPath, Path backupDir) {
        this.dbPath = dbPath;
        this.backupDir = backupDir;
    }

    public void initialize() throws Exception {
        Class.forName("org.sqlite.JDBC");
        Path parent = dbPath.toAbsolutePath().getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        Files.createDirectories(backupDir);

        try (Connection connection = open()) {
            try (Statement statement = connection.createStatement()) {
                statement.execute("PRAGMA journal_mode=WAL");
                statement.execute("PRAGMA busy_timeout=5000");
                statement.execute(
                        "CREATE TABLE IF NOT EXISTS schedule ("
                                + "id INTEGER PRIMARY KEY CHECK (id = 1),"
                                + "revision INTEGER NOT NULL,"
                                + "payload TEXT NOT NULL,"
                                + "updated_at TEXT NOT NULL,"
                                + "updated_by TEXT NOT NULL"
                                + ")");
                statement.execute(
                        "CREATE TABLE IF NOT EXISTS presence ("
                                + "member_id TEXT PRIMARY KEY,"
                                + "last_seen_at TEXT NOT NULL"
                                + ")");
                statement.execute(
                        "CREATE TABLE IF NOT EXISTS meta ("
                                + "key TEXT PRIMARY KEY,"
                                + "value TEXT NOT NULL"
                                + ")");
            }
            if (readRecord(connection) == null) {
                ScheduleData seed = ScheduleData.seed();
                try (PreparedStatement statement = connection.prepareStatement(
                        "INSERT INTO schedule (id, revision, payload, updated_at, updated_by) "
                                + "VALUES (1, ?, ?, ?, ?)")) {
                    statement.setLong(1, seed.revision);
                    statement.setString(2, mapper.writeValueAsString(seed));
                    statement.setString(3, seed.updatedAt);
                    statement.setString(4, seed.updatedBy);
                    statement.executeUpdate();
                }
                backup(seed);
                LOG.info("初始化轮协数据库");
            }
            migrateLegacySeed(connection);
            migratePresenceReset(connection);
        }
    }

    /**
     * 在线状态上线时，历史上无法确认谁真正用过功能，统一重置为“未验证”。
     * 之后成员姓名验证成功会自动重新标记，并写入在线心跳。
     */
    private void migratePresenceReset(Connection connection) throws Exception {
        if (readMeta(connection, "presence_reset_v1") != null) {
            return;
        }
        Record current = readRecord(connection);
        boolean changed = false;
        if (current != null) {
            for (Member member : current.schedule.members) {
                if (Boolean.TRUE.equals(member.verified) || member.verifiedAt != null) {
                    member.verified = Boolean.FALSE;
                    member.verifiedAt = null;
                    changed = true;
                }
            }
            if (changed) {
                current.schedule.revision = current.revision + 1;
                current.schedule.updatedAt = Instant.now().toString();
                current.schedule.updatedBy = "system:presence-reset";
                try (PreparedStatement statement = connection.prepareStatement(
                        "UPDATE schedule SET revision=?, payload=?, updated_at=?, updated_by=? WHERE id=1")) {
                    statement.setLong(1, current.schedule.revision);
                    statement.setString(2, mapper.writeValueAsString(current.schedule));
                    statement.setString(3, current.schedule.updatedAt);
                    statement.setString(4, current.schedule.updatedBy);
                    statement.executeUpdate();
                }
                backup(current.schedule);
            }
        }
        try (Statement statement = connection.createStatement()) {
            statement.executeUpdate("DELETE FROM presence");
        }
        writeMeta(connection, "presence_reset_v1", Instant.now().toString());
        LOG.info("已重置所有成员验证状态与在线记录");
    }

    /** 成员姓名验证成功后写入验证状态，返回 verifiedAt；成员不存在时返回 null。 */
    public String markVerified(String memberId) throws Exception {
        for (int attempt = 0; attempt < 3; attempt++) {
            Record current = read();
            Member target = null;
            for (Member member : current.schedule.members) {
                if (memberId.equals(member.id)) {
                    target = member;
                    break;
                }
            }
            if (target == null) {
                return null;
            }
            if (Boolean.TRUE.equals(target.verified) && target.verifiedAt != null) {
                return target.verifiedAt;
            }
            String verifiedAt = target.verifiedAt == null
                    ? Instant.now().toString()
                    : target.verifiedAt;
            target.verified = Boolean.TRUE;
            target.verifiedAt = verifiedAt;
            // 验证状态属于成员元数据，不推进 revision，避免管理员编辑时被误判冲突
            current.schedule.updatedAt = Instant.now().toString();
            current.schedule.updatedBy = "system:verify";
            if (writeIfRevision(current.revision, current.schedule)) {
                return verifiedAt;
            }
        }
        throw new IllegalStateException("写入成员验证状态失败");
    }

    /** 记录成员最近一次在线时间（不进 revision，不影响轮协编辑冲突）。 */
    public void touchPresence(String memberId, Instant now) throws Exception {
        try (Connection connection = open();
                PreparedStatement statement = connection.prepareStatement(
                        "INSERT INTO presence (member_id, last_seen_at) VALUES (?, ?) "
                                + "ON CONFLICT(member_id) DO UPDATE SET last_seen_at=excluded.last_seen_at")) {
            statement.setString(1, memberId);
            statement.setString(2, now.toString());
            statement.executeUpdate();
        }
    }

    /** memberId -> 最近在线时间 */
    public Map<String, String> readPresence() throws Exception {
        Map<String, String> result = new LinkedHashMap<>();
        try (Connection connection = open();
                Statement statement = connection.createStatement();
                ResultSet resultSet = statement.executeQuery(
                        "SELECT member_id, last_seen_at FROM presence")) {
            while (resultSet.next()) {
                result.put(resultSet.getString("member_id"), resultSet.getString("last_seen_at"));
            }
        }
        return result;
    }

    private String readMeta(Connection connection, String key) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT value FROM meta WHERE key=?")) {
            statement.setString(1, key);
            try (ResultSet resultSet = statement.executeQuery()) {
                return resultSet.next() ? resultSet.getString("value") : null;
            }
        }
    }

    private void writeMeta(Connection connection, String key, String value) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "INSERT INTO meta (key, value) VALUES (?, ?) "
                        + "ON CONFLICT(key) DO UPDATE SET value=excluded.value")) {
            statement.setString(1, key);
            statement.setString(2, value);
            statement.executeUpdate();
        }
    }

    /**
     * 旧版本自动种了一个名为“管理员”的示例成员，会让管理页看起来像在提示角色。
     * 只在“只有一个示例成员且没有任何轮协”时清理，避免误删真实数据。
     */
    private void migrateLegacySeed(Connection connection) throws Exception {
        Record current = readRecord(connection);
        if (current == null) {
            return;
        }
        ScheduleData data = current.schedule;
        if (data.members.size() != 1) {
            return;
        }
        Member only = data.members.get(0);
        if (!"m_admin".equals(only.id) || !"管理员".equals(only.name)) {
            return;
        }
        if (data.assignments != null && !data.assignments.isEmpty()) {
            return;
        }
        data.members.clear();
        if (data.rotation != null) {
            data.rotation.removeIf("m_admin"::equals);
        }
        data.revision = current.revision + 1;
        data.updatedAt = Instant.now().toString();
        data.updatedBy = "system";
        try (PreparedStatement statement = connection.prepareStatement(
                "UPDATE schedule SET revision=?, payload=?, updated_at=?, updated_by=? WHERE id=1")) {
            statement.setLong(1, data.revision);
            statement.setString(2, mapper.writeValueAsString(data));
            statement.setString(3, data.updatedAt);
            statement.setString(4, data.updatedBy);
            statement.executeUpdate();
        }
        backup(data);
        LOG.info("已清理旧版示例成员“管理员”");
    }

    public Record read() throws Exception {
        try (Connection connection = open()) {
            Record record = readRecord(connection);
            if (record == null) {
                throw new IllegalStateException("轮协表不存在");
            }
            return record;
        }
    }

    public boolean writeIfRevision(long baseRevision, ScheduleData schedule) throws Exception {
        try (Connection connection = open()) {
            connection.setAutoCommit(false);
            try (PreparedStatement statement = connection.prepareStatement(
                    "UPDATE schedule SET revision=?, payload=?, updated_at=?, updated_by=? "
                            + "WHERE id=1 AND revision=?")) {
                statement.setLong(1, schedule.revision);
                statement.setString(2, mapper.writeValueAsString(schedule));
                statement.setString(3, schedule.updatedAt);
                statement.setString(4, schedule.updatedBy);
                statement.setLong(5, baseRevision);
                int updated = statement.executeUpdate();
                if (updated == 0) {
                    connection.rollback();
                    return false;
                }
                connection.commit();
            } catch (Exception e) {
                connection.rollback();
                throw e;
            }
            backup(schedule);
            return true;
        }
    }

    private Record readRecord(Connection connection) throws SQLException, IOException {
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT revision, payload FROM schedule WHERE id=1");
             ResultSet resultSet = statement.executeQuery()) {
            if (!resultSet.next()) {
                return null;
            }
            long revision = resultSet.getLong("revision");
            String payload = resultSet.getString("payload");
            ScheduleData data;
            try {
                data = mapper.readValue(payload, ScheduleData.class);
            } catch (Exception e) {
                throw new IllegalStateException("轮协数据 JSON 损坏，请用备份文件恢复", e);
            }
            if (data == null) {
                throw new IllegalStateException("轮协数据为空");
            }
            data.revision = revision;
            if (data.updatedAt == null) {
                data.updatedAt = Instant.EPOCH.toString();
            }
            if (data.updatedBy == null) {
                data.updatedBy = "system";
            }
            if (data.members == null) {
                data.members = new ArrayList<>();
            }
            Set<Integer> usedSeq = new LinkedHashSet<>();
            int nextSeq = 1;
            for (Member member : data.members) {
                Integer seq = member.seq;
                if (seq == null || seq <= 0 || !usedSeq.add(seq)) {
                    while (usedSeq.contains(nextSeq)) {
                        nextSeq++;
                    }
                    member.seq = nextSeq;
                    usedSeq.add(nextSeq);
                }
            }
            if (data.assignments == null) {
                data.assignments = new LinkedHashMap<>();
            }
            if (data.rotation == null) {
                data.rotation = new ArrayList<>();
            }
            if (data.changeLog == null) {
                data.changeLog = new ArrayList<>();
            }
            return new Record(data, revision);
        }
    }

    private Connection open() throws SQLException {
        Connection connection = DriverManager.getConnection("jdbc:sqlite:" + dbPath.toAbsolutePath());
        try (Statement statement = connection.createStatement()) {
            statement.execute("PRAGMA busy_timeout=5000");
        }
        return connection;
    }

    private void backup(ScheduleData data) {
        try {
            Files.createDirectories(backupDir);
            String json = mapper.writerWithDefaultPrettyPrinter().writeValueAsString(data);
            Files.writeString(
                    backupDir.resolve("schedule-r" + data.revision + ".json"),
                    json,
                    StandardCharsets.UTF_8);
            Files.writeString(
                    backupDir.resolve("schedule-latest.json"),
                    json,
                    StandardCharsets.UTF_8);
        } catch (Exception e) {
            LOG.log(Level.WARNING, "轮协备份写入失败（不影响本次提交）", e);
        }
    }

    public static class Record {
        public final ScheduleData schedule;
        public final long revision;

        public Record(ScheduleData schedule, long revision) {
            this.schedule = schedule;
            this.revision = revision;
        }
    }
}
