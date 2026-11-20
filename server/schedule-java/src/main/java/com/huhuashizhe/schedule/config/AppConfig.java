package com.huhuashizhe.schedule.config;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Properties;

/**
 * 服务配置。
 *
 * 查找顺序：
 * 1. -Dschedule.config=C:/path/config.properties
 * 2. 环境变量 SCHEDULE_CONFIG
 * 3. 当前工作目录 config/config.properties
 * 4. %USERPROFILE%/.huhuashizhe-schedule/config.properties
 * 5. classpath:/config.properties
 */
public final class AppConfig {
    public final String scheduleKey;
    public final String adminKey;
    public final String tokenSecret;
    public final Path dbPath;
    public final Path backupDir;
    public final long memberTokenTtlSeconds;
    public final long adminTokenTtlSeconds;
    public final Path configPath;

    private AppConfig(
            String scheduleKey,
            String adminKey,
            String tokenSecret,
            Path dbPath,
            Path backupDir,
            long memberTokenTtlSeconds,
            long adminTokenTtlSeconds,
            Path configPath) {
        this.scheduleKey = scheduleKey;
        this.adminKey = adminKey;
        this.tokenSecret = tokenSecret;
        this.dbPath = dbPath;
        this.backupDir = backupDir;
        this.memberTokenTtlSeconds = memberTokenTtlSeconds;
        this.adminTokenTtlSeconds = adminTokenTtlSeconds;
        this.configPath = configPath;
    }

    public static AppConfig load() {
        Properties properties = new Properties();
        Path configPath = resolveConfigPath();
        try {
            if (configPath != null) {
                try (Reader reader = Files.newBufferedReader(configPath, StandardCharsets.UTF_8)) {
                    properties.load(reader);
                }
            } else {
                try (InputStream in = AppConfig.class.getResourceAsStream("/config.properties")) {
                    if (in != null) {
                        properties.load(new InputStreamReader(in, StandardCharsets.UTF_8));
                    }
                }
            }
        } catch (IOException e) {
            throw new IllegalStateException("读取排班服务配置失败: " + configPath, e);
        }

        String scheduleKey = trim(properties.getProperty("schedule.key"));
        String adminKey = trim(properties.getProperty("admin.key"));
        String tokenSecret = trim(properties.getProperty("token.secret"));

        if (scheduleKey.isEmpty() || adminKey.isEmpty() || tokenSecret.isEmpty()) {
            throw new IllegalStateException(
                    "排班服务未配置：请设置 schedule.key、admin.key、token.secret。"
                            + " 配置文件位置：" + (configPath == null ? "classpath:/config.properties" : configPath));
        }
        if (scheduleKey.equals(adminKey)) {
            throw new IllegalStateException("schedule.key 和 admin.key 不能相同");
        }
        if (tokenSecret.length() < 32) {
            throw new IllegalStateException("token.secret 至少需要 32 位随机字符");
        }

        Path userDir = Paths.get(System.getProperty("user.home"), ".huhuashizhe-schedule");
        Path dbPath = pathOrDefault(properties.getProperty("db.path"), userDir.resolve("schedule.db"));
        Path backupDir = pathOrDefault(properties.getProperty("backup.dir"), userDir.resolve("backups"));

        long memberTtl = longOrDefault(properties.getProperty("member.token.ttl.seconds"), 365L * 24 * 60 * 60);
        long adminTtl = longOrDefault(properties.getProperty("admin.token.ttl.seconds"), 90L * 24 * 60 * 60);
        if (memberTtl <= 0 || adminTtl <= 0) {
            throw new IllegalStateException("token TTL 必须大于 0");
        }

        return new AppConfig(
                scheduleKey,
                adminKey,
                tokenSecret,
                dbPath.toAbsolutePath().normalize(),
                backupDir.toAbsolutePath().normalize(),
                memberTtl,
                adminTtl,
                configPath == null ? null : configPath.toAbsolutePath().normalize());
    }

    private static Path resolveConfigPath() {
        String system = System.getProperty("schedule.config");
        if (system != null && !system.trim().isEmpty()) {
            return Paths.get(system.trim());
        }
        String env = System.getenv("SCHEDULE_CONFIG");
        if (env != null && !env.trim().isEmpty()) {
            return Paths.get(env.trim());
        }
        Path local = Paths.get("config", "config.properties");
        if (Files.isRegularFile(local)) {
            return local;
        }
        Path home = Paths.get(System.getProperty("user.home"), ".huhuashizhe-schedule", "config.properties");
        if (Files.isRegularFile(home)) {
            return home;
        }
        return null;
    }

    private static Path pathOrDefault(String value, Path fallback) {
        String trimmed = trim(value);
        return trimmed.isEmpty() ? fallback : Paths.get(trimmed);
    }

    private static long longOrDefault(String value, long fallback) {
        try {
            String trimmed = trim(value);
            return trimmed.isEmpty() ? fallback : Long.parseLong(trimmed);
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    private static String trim(String value) {
        return value == null ? "" : value.trim();
    }
}
