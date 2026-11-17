package com.huhuashizhe.schedule.db;

import com.huhuashizhe.schedule.model.Message;
import com.huhuashizhe.schedule.model.MessagesResponse;
import com.huhuashizhe.schedule.model.Reply;
import com.huhuashizhe.schedule.service.ValidationException;

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
import java.util.List;
import java.util.NoSuchElementException;
import java.util.Objects;
import java.util.UUID;

/**
 * 匿名留言池：
 * - 服务端只保存随机的匿名 ID，不保存成员姓名，管理员也无法反查
 * - 普通成员只能删除自己的留言/回复，管理员可删除任意内容
 * - 删除留言时外键级联删除其回复
 */
public class MessageRepository {
    private static final int MAX_CONTENT_LENGTH = 1000;

    private final Path dbPath;

    public MessageRepository(Path dbPath) {
        this.dbPath = dbPath;
    }

    public void initialize() throws Exception {
        Class.forName("org.sqlite.JDBC");
        try (Connection connection = open()) {
            try (Statement statement = connection.createStatement()) {
                statement.execute("CREATE TABLE IF NOT EXISTS messages ("
                        + "id TEXT PRIMARY KEY,"
                        + "author_anon_id TEXT NOT NULL,"
                        + "content TEXT NOT NULL,"
                        + "created_at TEXT NOT NULL"
                        + ")");
                statement.execute("CREATE TABLE IF NOT EXISTS message_replies ("
                        + "id TEXT PRIMARY KEY,"
                        + "message_id TEXT NOT NULL,"
                        + "author_anon_id TEXT NOT NULL,"
                        + "content TEXT NOT NULL,"
                        + "created_at TEXT NOT NULL,"
                        + "FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE"
                        + ")");
            }
        }
    }

    public List<Message> list(String anonId) throws Exception {
        String normalizedAnon = normalizeAnonId(anonId);
        List<Message> result = new ArrayList<>();
        try (Connection connection = open()) {
            try (PreparedStatement statement = connection.prepareStatement(
                    "SELECT id, content, created_at, author_anon_id FROM messages ORDER BY created_at DESC");
                 ResultSet resultSet = statement.executeQuery()) {
                while (resultSet.next()) {
                    Message message = new Message();
                    message.id = resultSet.getString("id");
                    message.content = resultSet.getString("content");
                    message.createdAt = resultSet.getString("created_at");
                    message.isMine = Objects.equals(normalizedAnon, resultSet.getString("author_anon_id"));
                    message.replies = listReplies(connection, message.id, normalizedAnon);
                    result.add(message);
                }
            }
        }
        return result;
    }

    public void createMessage(String anonId, String content) throws Exception {
        String normalizedAnon = requireAnonId(anonId);
        String normalizedContent = requireContent(content);
        try (Connection connection = open();
             PreparedStatement statement = connection.prepareStatement(
                     "INSERT INTO messages (id, author_anon_id, content, created_at) VALUES (?, ?, ?, ?)")) {
            statement.setString(1, "msg_" + UUID.randomUUID().toString().replace("-", ""));
            statement.setString(2, normalizedAnon);
            statement.setString(3, normalizedContent);
            statement.setString(4, Instant.now().toString());
            statement.executeUpdate();
        }
    }

    public void createReply(String messageId, String anonId, String content) throws Exception {
        String normalizedAnon = requireAnonId(anonId);
        String normalizedContent = requireContent(content);
        String normalizedId = trim(messageId);
        try (Connection connection = open()) {
            try (PreparedStatement exists = connection.prepareStatement(
                    "SELECT 1 FROM messages WHERE id=?")) {
                exists.setString(1, normalizedId);
                try (ResultSet resultSet = exists.executeQuery()) {
                    if (!resultSet.next()) {
                        throw new NoSuchElementException("留言不存在或已被删除");
                    }
                }
            }
            try (PreparedStatement statement = connection.prepareStatement(
                    "INSERT INTO message_replies (id, message_id, author_anon_id, content, created_at) "
                            + "VALUES (?, ?, ?, ?, ?)")) {
                statement.setString(1, "rpl_" + UUID.randomUUID().toString().replace("-", ""));
                statement.setString(2, normalizedId);
                statement.setString(3, normalizedAnon);
                statement.setString(4, normalizedContent);
                statement.setString(5, Instant.now().toString());
                statement.executeUpdate();
            }
        }
    }

    public void deleteMessage(String messageId, String anonId, boolean admin) throws Exception {
        String normalizedAnon = trim(anonId);
        try (Connection connection = open()) {
            String author = findAuthor(connection, "messages", messageId);
            if (author == null) {
                throw new NoSuchElementException("留言不存在或已被删除");
            }
            if (!admin && !Objects.equals(author, normalizedAnon)) {
                throw new SecurityException("只能删除自己的留言");
            }
            try (PreparedStatement statement = connection.prepareStatement(
                    "DELETE FROM messages WHERE id=?")) {
                statement.setString(1, messageId);
                statement.executeUpdate();
            }
        }
    }

    public void deleteReply(String replyId, String anonId, boolean admin) throws Exception {
        String normalizedAnon = trim(anonId);
        try (Connection connection = open()) {
            String author = findAuthor(connection, "message_replies", replyId);
            if (author == null) {
                throw new NoSuchElementException("回复不存在或已被删除");
            }
            if (!admin && !Objects.equals(author, normalizedAnon)) {
                throw new SecurityException("只能删除自己的回复");
            }
            try (PreparedStatement statement = connection.prepareStatement(
                    "DELETE FROM message_replies WHERE id=?")) {
                statement.setString(1, replyId);
                statement.executeUpdate();
            }
        }
    }

    private List<Reply> listReplies(Connection connection, String messageId, String anonId)
            throws SQLException {
        List<Reply> replies = new ArrayList<>();
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT id, content, created_at, author_anon_id FROM message_replies "
                        + "WHERE message_id=? ORDER BY created_at ASC")) {
            statement.setString(1, messageId);
            try (ResultSet resultSet = statement.executeQuery()) {
                while (resultSet.next()) {
                    Reply reply = new Reply();
                    reply.id = resultSet.getString("id");
                    reply.content = resultSet.getString("content");
                    reply.createdAt = resultSet.getString("created_at");
                    reply.isMine = Objects.equals(anonId, resultSet.getString("author_anon_id"));
                    replies.add(reply);
                }
            }
        }
        return replies;
    }

    private String findAuthor(Connection connection, String table, String id) throws SQLException {
        String safeTable = "messages".equals(table) ? "messages" : "message_replies";
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT author_anon_id FROM " + safeTable + " WHERE id=?")) {
            statement.setString(1, id);
            try (ResultSet resultSet = statement.executeQuery()) {
                return resultSet.next() ? resultSet.getString("author_anon_id") : null;
            }
        }
    }

    private Connection open() throws SQLException {
        Connection connection = DriverManager.getConnection("jdbc:sqlite:" + dbPath.toAbsolutePath());
        try (Statement statement = connection.createStatement()) {
            statement.execute("PRAGMA busy_timeout=5000");
            statement.execute("PRAGMA foreign_keys=ON");
        }
        return connection;
    }

    private String requireAnonId(String value) {
        String anonId = trim(value);
        if (anonId.isEmpty() || anonId.length() > 128) {
            throw new ValidationException("匿名标识无效");
        }
        return anonId;
    }

    private String normalizeAnonId(String value) {
        String anonId = trim(value);
        return anonId.length() > 128 ? anonId.substring(0, 128) : anonId;
    }

    private String requireContent(String value) {
        String content = value == null ? "" : value.trim();
        if (content.isEmpty()) {
            throw new ValidationException("留言内容不能为空");
        }
        if (content.length() > MAX_CONTENT_LENGTH) {
            throw new ValidationException("留言内容不能超过 " + MAX_CONTENT_LENGTH + " 个字");
        }
        return content;
    }

    private static String trim(String value) {
        return value == null ? "" : value.trim();
    }
}
