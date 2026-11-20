package com.huhuashizhe.schedule.service;

import java.time.LocalDate;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * AI 代理的基础限流：
 * - 单 IP 10 分钟内最多 20 次，防止脚本盗刷
 * - 单 IP 每天最多 100 次
 * - 全局每天最多 2000 次，给费用兜底
 *
 * 单实例内存计数，服务重启后归零；家用/团队单机服务足够。
 */
public class AiQuota {
    private static final int WINDOW_MINUTES = 10;
    private static final int WINDOW_MAX = 20;
    private static final int IP_DAILY_MAX = 100;
    private static final int GLOBAL_DAILY_MAX = 2000;

    private final ConcurrentHashMap<String, Deque<Long>> windows = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, IpDayCounter> daily = new ConcurrentHashMap<>();
    private final AtomicInteger globalCount = new AtomicInteger();
    private volatile LocalDate globalDay = LocalDate.now();

    public boolean allow(String ip) {
        long now = System.currentTimeMillis();
        Deque<Long> queue = windows.computeIfAbsent(ip, k -> new ArrayDeque<>());
        synchronized (queue) {
            while (!queue.isEmpty() && now - queue.peekFirst() > WINDOW_MINUTES * 60_000L) {
                queue.pollFirst();
            }
            if (queue.size() >= WINDOW_MAX) {
                return false;
            }
            queue.addLast(now);
        }

        LocalDate today = LocalDate.now();
        IpDayCounter counter = daily.computeIfAbsent(ip, k -> new IpDayCounter(today));
        synchronized (counter) {
            if (!today.equals(counter.day)) {
                counter.day = today;
                counter.count = 0;
            }
            if (counter.count >= IP_DAILY_MAX) {
                return false;
            }
            counter.count++;
        }

        synchronized (globalCount) {
            if (!today.equals(globalDay)) {
                globalDay = today;
                globalCount.set(0);
            }
            if (globalCount.incrementAndGet() > GLOBAL_DAILY_MAX) {
                globalCount.decrementAndGet();
                return false;
            }
        }
        cleanup();
        return true;
    }

    private void cleanup() {
        if (windows.size() <= 5000 && daily.size() <= 5000) {
            return;
        }
        long now = System.currentTimeMillis();
        windows.entrySet().removeIf(entry -> {
            Deque<Long> queue = entry.getValue();
            synchronized (queue) {
                return queue.isEmpty()
                        || now - queue.peekLast() > WINDOW_MINUTES * 60_000L;
            }
        });
        LocalDate today = LocalDate.now();
        daily.entrySet().removeIf(entry -> !today.equals(entry.getValue().day));
    }

    private static final class IpDayCounter {
        private LocalDate day;
        private int count;

        private IpDayCounter(LocalDate day) {
            this.day = day;
        }
    }
}
