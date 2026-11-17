package com.huhuashizhe.schedule.service;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 单实例内存限流：每 IP 每分钟最多 10 次 /auth 尝试。
 * 家用单机服务足够；如果以后多实例，换成 Redis。
 */
public class RateLimiter {
    private static final int WINDOW_SECONDS = 60;
    private static final int MAX_ATTEMPTS = 10;

    private final ConcurrentHashMap<String, Deque<Long>> attempts = new ConcurrentHashMap<>();

    public boolean allow(String key) {
        long now = System.currentTimeMillis();
        Deque<Long> queue = attempts.computeIfAbsent(key, k -> new ArrayDeque<>());
        synchronized (queue) {
            while (!queue.isEmpty() && now - queue.peekFirst() > WINDOW_SECONDS * 1000L) {
                queue.pollFirst();
            }
            if (queue.size() >= MAX_ATTEMPTS) {
                return false;
            }
            queue.addLast(now);
            return true;
        }
    }

    public void cleanup() {
        if (attempts.size() <= 5000) {
            return;
        }
        long now = System.currentTimeMillis();
        attempts.entrySet().removeIf(entry -> {
            Deque<Long> queue = entry.getValue();
            synchronized (queue) {
                return queue.isEmpty()
                        || now - queue.peekLast() > WINDOW_SECONDS * 1000L;
            }
        });
    }
}
