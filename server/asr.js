import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const IAT_HOST = 'iat-api.xfyun.cn';
const IAT_PATH = '/v2/iat';
const SAMPLE_RATE = 16000;
const MAX_SECONDS = 60;

// 讯飞语音听写支持的方言参数
const SUPPORTED_ACCENTS = new Set([
  'mandarin',
  'cantonese',
  'sichuanese',
  'henanese',
  'northeastern',
  'hunanese',
]);

/** 读取 config.properties，支持 iflytek.* 或 xfyun.* 两种键名 */
function readProperties() {
  const candidates = [
    process.env.FORUM_CONFIG,
    path.join(__dirname, '..', 'config', 'config.properties'),
    'C:\\huhuashizhe\\config\\config.properties',
  ].filter(Boolean);
  for (const file of candidates) {
    try {
      if (!fs.existsSync(file)) continue;
      const map = {};
      for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
        const text = line.trim();
        if (!text || text.startsWith('#')) continue;
        const index = text.indexOf('=');
        if (index < 0) continue;
        map[text.slice(0, index).trim()] = text.slice(index + 1).trim();
      }
      return map;
    } catch {
      // 读不到配置文件时继续尝试下一个
    }
  }
  return {};
}

function loadCredentials() {
  const props = readProperties();
  const pick = (...keys) => {
    for (const key of keys) {
      const value = props[key];
      if (value) return value;
    }
    return '';
  };
  return {
    appId: (
      process.env.IFLYTEK_APP_ID || pick('iflytek.appId', 'xfyun.appId')
    ).trim(),
    apiKey: (
      process.env.IFLYTEK_API_KEY || pick('iflytek.apiKey', 'xfyun.apiKey')
    ).trim(),
    apiSecret: (
      process.env.IFLYTEK_API_SECRET || pick('iflytek.apiSecret', 'xfyun.apiSecret')
    ).trim(),
  };
}

/** 按讯飞要求生成带签名的 WebSocket 地址 */
function buildIatUrl({ apiKey, apiSecret }) {
  const date = new Date().toUTCString();
  const origin = `host: ${IAT_HOST}\ndate: ${date}\nGET ${IAT_PATH} HTTP/1.1`;
  const signature = crypto
    .createHmac('sha256', apiSecret)
    .update(origin)
    .digest('base64');
  const authorizationOrigin =
    `api_key="${apiKey}", algorithm="hmac-sha256", ` +
    `headers="host date request-line", signature="${signature}"`;
  const authorization = Buffer.from(authorizationOrigin).toString('base64');
  return (
    `wss://${IAT_HOST}${IAT_PATH}?authorization=${encodeURIComponent(authorization)}` +
    `&date=${encodeURIComponent(date)}&host=${IAT_HOST}`
  );
}

/** 将 16k/16bit/单声道 PCM 分片发送给讯飞，拼出普通话文字 */
async function recognizePcm(pcm, accent, creds) {
  const { default: WebSocket } = await import('ws');
  const url = buildIatUrl(creds);

  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    let text = '';
    let finished = false;

    const finish = (error, result) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      if (error) {
        try {
          ws.terminate();
        } catch {
          // 连接已关闭
        }
        reject(error);
        return;
      }
      try {
        ws.close();
      } catch {
        // 忽略关闭异常
      }
      resolve(result);
    };

    const timer = setTimeout(() => finish(new Error('讯飞识别超时')), 30000);

    ws.on('open', () => {
      const chunkSize = 1280; // 40ms 音频
      let offset = 0;
      const sendNext = () => {
        if (finished) return;
        if (offset === 0) {
          const end = Math.min(chunkSize, pcm.length);
          ws.send(
            JSON.stringify({
              common: { app_id: creds.appId },
              business: {
                language: 'zh_cn',
                domain: 'iat',
                accent,
                vad_eos: 10000,
              },
              data: {
                status: 0,
                format: 'audio/L16;rate=16000',
                encoding: 'raw',
                audio: pcm.subarray(0, end).toString('base64'),
              },
            }),
          );
          offset = end;
        } else if (offset < pcm.length) {
          const end = Math.min(offset + chunkSize, pcm.length);
          ws.send(
            JSON.stringify({
              data: {
                status: 1,
                format: 'audio/L16;rate=16000',
                encoding: 'raw',
                audio: pcm.subarray(offset, end).toString('base64'),
              },
            }),
          );
          offset = end;
        } else {
          ws.send(
            JSON.stringify({
              data: {
                status: 2,
                format: 'audio/L16;rate=16000',
                encoding: 'raw',
                audio: '',
              },
            }),
          );
          return;
        }
        setTimeout(sendNext, 40);
      };
      sendNext();
    });

    ws.on('message', (raw) => {
      let message;
      try {
        message = JSON.parse(raw.toString());
      } catch {
        return;
      }
      if (message.code !== 0) {
        finish(new Error(`讯飞返回 ${message.code}: ${message.message || ''}`));
        return;
      }
      const data = message.data || {};
      if (data.result?.ws) {
        for (const item of data.result.ws) {
          for (const cw of item.cw || []) {
            if (cw.w) text += cw.w;
          }
        }
      }
      if (data.status === 2) finish(null, text.trim());
    });

    ws.on('error', (error) => finish(error));
    ws.on('close', () => finish(new Error('讯飞连接已断开')));
  });
}

/** 注册方言语音识别接口 */
export function registerAsrRoutes(app) {
  app.post('/api/asr', async (req, res) => {
    const body = req.body ?? {};
    const audio = typeof body.audio === 'string' ? body.audio : '';
    const dialect =
      typeof body.dialect === 'string' && body.dialect
        ? body.dialect
        : 'mandarin';

    if (!audio) return res.status(400).json({ error: '缺少音频数据' });
    if (!SUPPORTED_ACCENTS.has(dialect)) {
      return res.status(400).json({ error: '不支持的方言' });
    }

    let pcm;
    try {
      pcm = Buffer.from(audio, 'base64');
    } catch {
      return res.status(400).json({ error: '音频数据格式不正确' });
    }
    // 兼容 WAV 文件：跳过文件头，只保留 PCM 数据
    if (pcm.length > 12 && pcm.toString('ascii', 0, 4) === 'RIFF') {
      const dataIndex = pcm.indexOf(Buffer.from('data', 'ascii'));
      if (dataIndex >= 0 && dataIndex + 8 <= pcm.length) {
        pcm = pcm.subarray(dataIndex + 8);
      }
    }
    if (pcm.length < SAMPLE_RATE) {
      return res.status(400).json({ error: '录音太短，请说完整一句再结束' });
    }
    if (pcm.length > SAMPLE_RATE * 2 * MAX_SECONDS) {
      return res.status(400).json({ error: `单次语音不能超过 ${MAX_SECONDS} 秒` });
    }

    const creds = loadCredentials();
    if (!creds.appId || !creds.apiKey || !creds.apiSecret) {
      return res
        .status(503)
        .json({ error: '方言识别服务未配置，请联系管理员' });
    }

    try {
      const text = await recognizePcm(pcm, dialect, creds);
      if (!text) {
        return res.status(422).json({ error: '没有识别到内容，请再说一次' });
      }
      res.json({ text });
    } catch (error) {
      console.error('讯飞方言识别失败:', error.message);
      res.status(502).json({ error: '方言识别失败，请稍后重试' });
    }
  });
}
