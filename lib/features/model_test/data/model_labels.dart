/// 模型类别标签（与 assets/models/classify_39.tflite 输出索引一一对应）
///
/// 顺序必须严格等于训练时 model.names 的顺序（ultralytics 按类别目录名 ASCII 排序），
/// 顺序错一位就会导致所有识别结果错位。
class ModelLabel {
  final String en; // 训练类别名
  final String zh; // 中文名称
  final String desc; // 问题简述
  final bool healthy; // 是否健康类（不采集、不预警）

  const ModelLabel({
    required this.en,
    required this.zh,
    required this.desc,
    this.healthy = false,
  });
}

const List<ModelLabel> kModelLabels = [
  ModelLabel(en: 'Apple___Apple_scab', zh: '苹果黑星病', desc: '叶片出现橄榄绿至黑色斑点，后期凹陷硬化，可致早期落叶。'),
  ModelLabel(en: 'Apple___Black_rot', zh: '苹果黑腐病', desc: '叶面出现同心轮纹状褐色斑，果实腐烂发黑。'),
  ModelLabel(en: 'Apple___Cedar_apple_rust', zh: '苹果雪松锈病', desc: '叶片正面亮黄色橙斑，背面生锈色刺状病斑。'),
  ModelLabel(en: 'Apple___healthy', zh: '苹果健康', desc: '叶片健康无病变。', healthy: true),
  ModelLabel(en: 'Background_without_leaves', zh: '背景干扰', desc: '画面中无可识别作物叶片。', healthy: true),
  ModelLabel(en: 'Blueberry___healthy', zh: '蓝莓健康', desc: '叶片健康无病变。', healthy: true),
  ModelLabel(en: 'Cherry___Powdery_mildew', zh: '樱桃白粉病', desc: '叶面出现白色粉状霉层，叶片卷曲黄化。'),
  ModelLabel(en: 'Cherry___healthy', zh: '樱桃健康', desc: '叶片健康无病变。', healthy: true),
  ModelLabel(en: 'Corn___Cercospora_leaf_spot Gray_leaf_spot', zh: '玉米灰斑病', desc: '叶面出现灰褐色长条形坏死斑，平行叶脉延伸。'),
  ModelLabel(en: 'Corn___Common_rust', zh: '玉米普通锈病', desc: '叶片散布红褐色至铁锈色脓疱状病斑。'),
  ModelLabel(en: 'Corn___Northern_Leaf_Blight', zh: '玉米北方褐斑病', desc: '叶面出现大型梭形灰绿色至灰褐色病斑。'),
  ModelLabel(en: 'Corn___healthy', zh: '玉米健康', desc: '叶片健康无病变。', healthy: true),
  ModelLabel(en: 'Grape___Black_rot', zh: '葡萄黑腐病', desc: '叶片生圆形褐色斑点并带黑色小点，果实干腐。'),
  ModelLabel(en: 'Grape___Esca_(Black_Measles)', zh: '葡萄黑麻疹病', desc: '叶面形成虎纹状条带坏死，果实干缩变黑。'),
  ModelLabel(en: 'Grape___Leaf_blight_(Isariopsis_Leaf_Spot)', zh: '葡萄褐斑病', desc: '叶片出现暗褐色不规则坏死斑，严重时大量落叶。'),
  ModelLabel(en: 'Grape___healthy', zh: '葡萄健康', desc: '叶片健康无病变。', healthy: true),
  ModelLabel(en: 'Orange___Haunglongbing_(Citrus_greening)', zh: '柑橘黄龙病', desc: '叶片斑驳黄化、不对称黄绿相间，果实畸形味苦。'),
  ModelLabel(en: 'Peach___Bacterial_spot', zh: '桃细菌性穿孔病', desc: '叶片出现紫褐色角斑并穿孔脱落，果实凹陷斑。'),
  ModelLabel(en: 'Peach___healthy', zh: '桃健康', desc: '叶片健康无病变。', healthy: true),
  ModelLabel(en: 'Pepper,_bell___Bacterial_spot', zh: '辣椒细菌性斑点病', desc: '叶面水渍状角斑转褐坏死，果实隆起黑斑。'),
  ModelLabel(en: 'Pepper,_bell___healthy', zh: '辣椒健康', desc: '叶片健康无病变。', healthy: true),
  ModelLabel(en: 'Potato___Early_blight', zh: '马铃薯早疫病', desc: '叶面出现同心轮纹的褐色靶状病斑。'),
  ModelLabel(en: 'Potato___Late_blight', zh: '马铃薯晚疫病', desc: '叶缘出现水渍状暗绿至褐色大斑，湿腐并伴白色霉层。'),
  ModelLabel(en: 'Potato___healthy', zh: '马铃薯健康', desc: '叶片健康无病变。', healthy: true),
  ModelLabel(en: 'Raspberry___healthy', zh: '树莓健康', desc: '叶片健康无病变。', healthy: true),
  ModelLabel(en: 'Soybean___healthy', zh: '大豆健康', desc: '叶片健康无病变。', healthy: true),
  ModelLabel(en: 'Squash___Powdery_mildew', zh: '南瓜白粉病', desc: '叶面覆盖白色粉状霉层，后期黄化枯萎。'),
  ModelLabel(en: 'Strawberry___Leaf_scorch', zh: '草莓焦斑病', desc: '叶缘出现紫红色不规则焦枯斑，叶脉间紫斑。'),
  ModelLabel(en: 'Strawberry___healthy', zh: '草莓健康', desc: '叶片健康无病变。', healthy: true),
  ModelLabel(en: 'Tomato___Bacterial_spot', zh: '番茄细菌性斑点病', desc: '叶面小水渍斑转深褐坏死，果实黑色小凸斑。'),
  ModelLabel(en: 'Tomato___Early_blight', zh: '番茄早疫病', desc: '下部叶片出现同心轮纹褐色大斑，似靶状。'),
  ModelLabel(en: 'Tomato___Late_blight', zh: '番茄晚疫病', desc: '叶片油渍状灰绿大斑迅速扩展，果实褐腐。'),
  ModelLabel(en: 'Tomato___Leaf_Mold', zh: '番茄叶霉病', desc: '叶背出现灰紫色霉层，叶面相应黄化斑。'),
  ModelLabel(en: 'Tomato___Septoria_leaf_spot', zh: '番茄斑枯病', desc: '叶面散布小圆形灰白斑，边缘褐色带小黑点。'),
  ModelLabel(en: 'Tomato___Spider_mites Two-spotted_spider_mite', zh: '番茄二斑叶螨危害', desc: '叶面密集针尖状褪绿斑点，叶片灰白干枯。'),
  ModelLabel(en: 'Tomato___Target_Spot', zh: '番茄靶斑病', desc: '叶面出现深褐色同心轮纹斑，幼叶扭曲。'),
  ModelLabel(en: 'Tomato___Tomato_Yellow_Leaf_Curl_Virus', zh: '番茄黄化曲叶病毒病', desc: '新叶黄化、向上卷曲呈杯状，严重时顶部丛簇。'),
  ModelLabel(en: 'Tomato___Tomato_mosaic_virus', zh: '番茄花叶病毒病', desc: '叶片黄绿相间花叶、卷曲畸形，植株矮化。'),
  ModelLabel(en: 'Tomato___healthy', zh: '番茄健康', desc: '叶片健康无病变。', healthy: true),
];

/// 判断类别是否为可预警的"作物问题"
bool isProblemClass(int index) {
  if (index < 0 || index >= kModelLabels.length) return false;
  return !kModelLabels[index].healthy;
}

/// 获取中文名称
String zhLabelOf(int index) {
  if (index < 0 || index >= kModelLabels.length) return '未知';
  return kModelLabels[index].zh;
}
