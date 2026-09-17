import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'help_detail_page.dart';

// ─── 데이터 모델 ───────────────────────────────────────────────────────────────

class HelpStep {
  final String text;
  final String? imageLabel; // 아직 사진 없는 자리 텍스트 placeholder
  final String? assetPath;  // 실제 삽입할 앱 내 asset 이미지 경로
  const HelpStep({required this.text, this.imageLabel, this.assetPath});
}

class HelpItem {
  final String title;
  final String description;
  final List<HelpStep> steps;
  const HelpItem({required this.title, required this.description, this.steps = const []});
}

class HelpCategory {
  final String title;
  final IconData icon;
  final List<String> roles; // 비어 있으면 전체 공개
  final List<HelpItem> items;
  const HelpCategory({required this.title, required this.icon, this.roles = const [], required this.items});
}

// ─── 1. 다시봄 시작하기 ────────────────────────────────────────────────────────

const _catStart = HelpCategory(
  title: '다시봄 시작하기',
  icon: Icons.rocket_launch_outlined,
  items: [
    HelpItem(
      title: '회원가입은 어떻게 하나요?',
      description: '다시봄은 이메일로 회원가입이 가능합니다. 가입 후 로그인하면 신고·제보, 예방등록 등 모든 기능을 이용할 수 있습니다.',
      steps: [
        HelpStep(text: '앱 시작 화면에서 "회원가입" 버튼을 탭합니다.', assetPath: 'assets/images/getting_started/image1.png'),
        HelpStep(text: '이메일, 비밀번호, 이름, 연락처를 입력합니다.', assetPath: 'assets/images/getting_started/image2.jpg'),
        HelpStep(text: '"가입하기" 버튼을 탭하면 가입이 완료됩니다.'),
      ],
    ),
    HelpItem(
      title: '로그인은 어떻게 하나요?',
      description: '가입한 이메일과 비밀번호로 로그인합니다.',
      steps: [
        HelpStep(text: '앱 시작 화면에서 이메일과 비밀번호를 입력합니다.', assetPath: 'assets/images/getting_started/image3.jpg'),
        HelpStep(text: '"로그인" 버튼을 탭합니다.'),
        HelpStep(text: '로그인 상태는 자동으로 유지됩니다. 앱을 닫아도 다시 로그인할 필요가 없습니다.'),
      ],
    ),
    HelpItem(
      title: '비밀번호를 잊어버렸어요.',
      description: '로그인 화면에서 비밀번호 찾기를 이용할 수 있습니다.',
      steps: [
        HelpStep(text: '로그인 화면에서 "비밀번호 찾기"를 탭합니다.', assetPath: 'assets/images/getting_started/image4.png'),
        HelpStep(text: '가입한 이메일 주소를 입력합니다.'),
        HelpStep(text: '해당 이메일로 전송된 안내에 따라 비밀번호를 재설정합니다.'),
      ],
    ),
    HelpItem(
      title: '게스트로 어떤 기능을 이용할 수 있나요?',
      description: '로그인 없이 게스트로 이용할 수 있는 기능은 다음과 같습니다.',
      steps: [
        HelpStep(text: '실종자 목록 및 상세 정보 조회'),
        HelpStep(text: '실종자 신고 (비회원 신고)'),
        HelpStep(text: '안전지도 시설 조회'),
      ],
    ),
    HelpItem(
      title: '로그아웃은 어떻게 하나요?',
      description: '설정 화면에서 로그아웃할 수 있습니다.',
      steps: [
        HelpStep(text: '화면 우측 상단 톱니바퀴 아이콘을 탭합니다.', assetPath: 'assets/images/getting_started/image5.png'),
        HelpStep(text: '가입한 이메일 주소를 입력합니다.'),
        HelpStep(text: '화면 하단의 "로그아웃" 버튼을 탭합니다.', assetPath: 'assets/images/getting_started/image6.png'),
        HelpStep(text: '확인 버튼을 탭하면 로그아웃됩니다.'),
      ],
    ),
    HelpItem(
      title: '앱에서 역할(권한)이란 무엇인가요?',
      description: '다시봄은 사용자 역할에 따라 이용할 수 있는 기능이 다릅니다.',
      steps: [
        HelpStep(text: '일반 회원: 실종 신고, 목격 제보, 예방등록 신청이 가능합니다.'),
        HelpStep(text: '보호자: 예방등록이 승인되면 자동으로 부여됩니다. 피보호자의 실시간 위치 확인이 가능합니다.'),
        HelpStep(text: '관리자: 신고 검토, 예방등록 승인·반려 권한이 있습니다.'),
        HelpStep(text: '현재 내 역할은 설정 화면 프로필 카드의 "권한" 항목에서 확인할 수 있습니다.', assetPath: 'assets/images/getting_started/image7.png'),
      ],
    ),
  ],
);

// ─── 2. 실종자 찾기 ────────────────────────────────────────────────────────────

const _catMissing = HelpCategory(
  title: '실종자 찾기',
  icon: Icons.person_search_outlined,
  items: [
    HelpItem(
      title: '실종자 목록은 어디서 볼 수 있나요?',
      description: '하단 탭의 "실종자" 메뉴에서 등록된 실종자 목록을 조회할 수 있습니다.',
      steps: [
        HelpStep(text: '하단 탭에서 "실종자" 아이콘을 탭합니다.', assetPath: 'assets/images/find_missing_person/image1.png'),
        HelpStep(text: '등록된 실종자 목록이 표시됩니다.', assetPath: 'assets/images/find_missing_person/image2.jpg'),
        HelpStep(text: '원하는 실종자 카드를 탭하면 상세 정보를 볼 수 있습니다.'),
      ],
    ),
    HelpItem(
      title: '실종자 상세 정보에서 무엇을 확인할 수 있나요?',
      description: '실종자 상세 페이지에서는 신체 특징, 실종 일시·장소, 사진 등 상세 정보를 확인할 수 있습니다.',
      steps: [
        HelpStep(text: '이름, 나이, 성별 등 기본 정보', assetPath: 'assets/images/find_missing_person/image3.jpg'),
        HelpStep(text: '키, 몸무게, 머리 색·스타일 등 신체 특징'),
        HelpStep(text: '실종 일시, 실종 장소'),
        HelpStep(text: '실종 당시 착용 의상 및 특이사항'),
        HelpStep(text: '등록된 사진'),
      ],
    ),
    HelpItem(
      title: '실종자를 목격했을 때는 어떻게 하나요?',
      description: '실종자를 목격한 경우 목격 제보를 남기거나 즉시 경찰에 신고해 주세요.',
      steps: [
        HelpStep(text: '실종자 상세 페이지에서 "목격 제보하기" 버튼을 탭합니다.', assetPath: 'assets/images/find_missing_person/image4.png'),
        HelpStep(text: '목격 위치, 시간, 특이사항을 최대한 자세히 입력합니다.'),
        HelpStep(text: '긴급한 상황이라면 112(경찰)에 즉시 신고해 주세요.'),
      ],
    ),
    HelpItem(
      title: '실종자를 찾았을 때는 어떻게 하나요?',
      description: '112에 신고하거나 앱을 통해 제보하면 담당 기관이 신고 상태를 업데이트합니다.',
      steps: [
        HelpStep(text: '112에 전화하여 발견 사실을 알립니다.'),
        HelpStep(text: '또는 앱에서 "실종자 상세 정보" 탭으로 이동하여 해당 실종자 프로필을 탭합니다.'),
        HelpStep(text: '하단의 "제보하기" 버튼을 탭하여 발견 사실을 제보합니다.'),
        HelpStep(text: '담당 기관이 내용을 확인한 후 신고 상태를 "신고완료"로 업데이트합니다.'),
        HelpStep(text: '신고자는 신고 현황에서 완료된 신고를 확인할 수 있습니다.'),
      ],
    ),
  ],
);

// ─── 3. 실종자 신고·제보 ──────────────────────────────────────────────────────

const _catReport = HelpCategory(
  title: '실종자 신고·제보',
  icon: Icons.campaign_outlined,
  items: [
    HelpItem(
      title: '실종 신고는 어떻게 하나요?',
      description: '실종자 신고는 하단 탭의 "신고·제보" 메뉴에서 할 수 있습니다. 비회원도 신고가 가능합니다.',
      steps: [
        HelpStep(text: '하단 탭에서 "신고·제보"를 탭합니다.', assetPath: 'assets/images/missing_report_and_tip/image1.png'),
        HelpStep(text: '실종자 이름, 나이, 실종 일시·장소를 입력합니다.', assetPath: 'assets/images/missing_report_and_tip/image2.jpg'),
        HelpStep(text: '신체 특징과 착용 의상을 최대한 자세히 입력합니다.'),
        HelpStep(text: '사진을 첨부하고 "신고하기" 버튼을 탭합니다.'),
      ],
    ),
    HelpItem(
      title: '목격 제보는 어떻게 하나요?',
      description: '실종자 상세 프로필에서 하단의 "제보하기" 버튼을 통해 목격 제보를 남길 수 있습니다.',
      steps: [
        HelpStep(text: '하단 탭에서 "실종자 상세 정보"를 탭합니다.'),
        HelpStep(text: '목격한 실종자의 카드를 탭하여 상세 정보 페이지로 이동합니다.'),
        HelpStep(text: '상세 페이지 하단의 "제보하기" 버튼을 탭합니다.'),
        HelpStep(text: '목격 위치, 시간, 특이사항을 입력합니다.'),
        HelpStep(text: '"제출" 버튼을 탭하면 제보가 접수됩니다.'),
      ],
    ),
    HelpItem(
      title: '내가 신고한 실종 신고는 어디서 확인하나요?',
      description: '하단 탭의 "실종신고"에서 상단 "신고 현황" 탭을 통해 내가 접수한 신고 목록을 확인할 수 있습니다.',
      steps: [
        HelpStep(text: '하단 탭에서 "실종신고"를 탭합니다.'),
        HelpStep(text: '상단의 "신고 현황" 탭을 선택합니다.'),
        HelpStep(text: '접수중 / 확인중 / 신고완료 필터로 상태별 조회가 가능합니다.'),
      ],
    ),
    HelpItem(
      title: '내가 작성한 목격 제보는 어디서 확인하나요?',
      description: '실종자 상세 프로필의 "제보하기"에서 상단 "제보 현황" 탭을 통해 내가 작성한 제보 목록을 확인할 수 있습니다.',
      steps: [
        HelpStep(text: '하단 탭에서 "실종자"를 탭한 후 아무 실종자 프로필을 탭합니다.'),
        HelpStep(text: '하단의 "제보하기" 버튼을 탭합니다.'),
        HelpStep(text: '상단의 "제보 현황" 탭을 선택합니다.'),
        HelpStep(text: '내가 작성한 제보 목록을 확인할 수 있습니다.'),
      ],
    ),
    HelpItem(
      title: '비회원으로 신고했는데 진행 상황은 어떻게 확인하나요?',
      description: '"신고 현황" 탭에서 신고 시 입력한 성명과 연락처로 조회할 수 있습니다.',
      steps: [
        HelpStep(text: '"신고 현황" 탭을 탭합니다.', assetPath: 'assets/images/missing_report_and_tip/image3.png'),
        HelpStep(text: '신고 시 입력한 성명과 연락처를 입력합니다.', assetPath: 'assets/images/missing_report_and_tip/image4.jpg'),
        HelpStep(text: '"조회하기" 버튼을 탭하면 내가 접수한 신고 목록이 표시됩니다.'),
      ],
    ),
    HelpItem(
      title: '신고·제보 내용을 수정할 수 있나요?',
      description: '신고·제보는 상태가 "접수중"일 때만 수정할 수 있습니다. "확인중" 상태에서는 수정이 불가하며, 본인이 작성한 신고·제보만 수정할 수 있습니다.',
      steps: [
        HelpStep(text: '수정하려는 신고·제보의 상태가 "접수중"인지 확인합니다.'),
        HelpStep(text: '신고 현황 또는 제보 현황에서 수정할 항목을 탭합니다.'),
        HelpStep(text: '상세 페이지에서 "수정" 버튼을 탭합니다.'),
        HelpStep(text: '내용을 수정하고 "수정완료" 버튼을 탭합니다.'),
      ],
    ),
    HelpItem(
      title: '신고 진행 상태는 무엇을 의미하나요?',
      description: '신고는 아래 3단계로 진행됩니다.',
      steps: [
        HelpStep(text: '접수중: 신고가 접수되어 담당자 확인을 기다리는 상태입니다.'),
        HelpStep(text: '확인중: 담당자가 신고 내용을 검토하고 있는 상태입니다.'),
        HelpStep(text: '등록완료: 신고 내용 검토가 완료되어 실종자 목록에 등록된 상태입니다.'),
        HelpStep(text: '거절됨: 중복 신고 등의 이유로 접수가 거절된 상태입니다.'),
      ],
    ),
    HelpItem(
      title: '등록 완료 후 실종자 정보는 어떻게 되나요?',
      description: '등록이 완료 처리되면 해당 실종자 정보를 실종자 상세 페이지에서 확인할 수 있습니다.',
      steps: [
        HelpStep(text: '"신고 현황"에서 완료된 신고 카드를 탭합니다.'),
        HelpStep(text: '연결된 실종자의 상세 정보 페이지로 이동합니다.'),
      ],
    ),
  ],
);

// ─── 4. 실종예방등록 ──────────────────────────────────────────────────────────

const _catRegister = HelpCategory(
  title: '실종예방등록',
  icon: Icons.app_registration_outlined,
  items: [
    HelpItem(
      title: '실종예방등록은 무엇인가요?',
      description: '실종예방등록은 치매 노인, 발달장애인 등 실종 위험이 있는 피보호자를 사전에 등록하는 서비스입니다. 등록 완료 후 뱃지를 통해 실시간 위치를 확인할 수 있습니다.',
      steps: [
        HelpStep(text: '피보호자 정보(이름, 사진, 신체 특징 등)를 사전 등록합니다.'),
        HelpStep(text: '담당자 검토 후 등록이 승인됩니다.'),
        HelpStep(text: '등록 완료 시 보호자 권한이 부여되고 뱃지로 실시간 위치 추적이 가능합니다.'),
      ],
    ),
    HelpItem(
      title: '피보호자는 어떻게 등록하나요?',
      description: '"실종예방등록" 메뉴에서 예방등록 신청을 할 수 있습니다.',
      steps: [
        HelpStep(text: '하단 탭에서 "실종예방등록" 탭을 선택합니다.', assetPath: 'assets/images/prevention_registration/image1.png'),
        HelpStep(text: '피보호자 이름, 성별, 생년월일, 주소 등 기본 정보를 입력합니다.', assetPath: 'assets/images/prevention_registration/image2.jpg'),
        HelpStep(text: '신체 특징, 건강 정보, 자주 가는 장소를 입력합니다.'),
        HelpStep(text: '사진을 등록하고 "신청하기" 버튼을 탭합니다.'),
        HelpStep(text: '담당자 검토 후 등록 여부가 결정됩니다. 결과는 "등록 현황"에서 확인하세요.'),
      ],
    ),
    HelpItem(
      title: '어떤 사진을 등록해야 하나요?',
      description: '정확한 신원 확인을 위해 다양한 각도의 최근 사진 등록을 권장합니다.',
      steps: [
        HelpStep(text: '정면 사진 (필수): 얼굴이 선명하게 보이는 최근 사진'),
        HelpStep(text: '전신 사진: 전체 신체 특징 확인용'),
        HelpStep(text: '좌·우 측면 사진: 측면 특징 확인용'),
        HelpStep(text: '가족 사진: 보호자 얼굴이 포함된 사진 (선택)'),
        HelpStep(text: '모자나 선글라스 등으로 얼굴이 가려지지 않은 사진을 등록해 주세요.'),
      ],
    ),
    HelpItem(
      title: '사진 검증은 무엇인가요?',
      description: '등록된 사진이 신원 확인에 적합한지 자동으로 분석하는 기능입니다. 검증 결과는 관리자가 승인 시 참고합니다.',
      steps: [
        HelpStep(text: '정상: 사진이 신원 확인에 적합한 상태입니다.'),
        HelpStep(text: '경고: 사진 품질이 다소 낮지만 사용 가능한 상태입니다.'),
        HelpStep(text: '오류: 사진이 부적합하거나 얼굴 인식이 어렵습니다. 교체를 권장합니다.'),
        HelpStep(text: '검증 결과가 좋지 않으면 등록 현황 상세 화면에서 사진을 교체할 수 있습니다.'),
      ],
    ),
    HelpItem(
      title: '등록 상태는 어디서 확인하나요?',
      description: '하단 탭의 "실종예방등록"에 들어가 상단의 "등록 현황" 탭에서 신청 진행 상태를 확인할 수 있습니다.',
      steps: [
        HelpStep(text: '하단 탭에서 "실종예방등록"을 탭합니다.'),
        HelpStep(text: '상단의 "등록 현황" 탭을 선택합니다.'),
        HelpStep(text: '접수중 / 확인중 / 등록완료 필터로 상태별 조회가 가능합니다.'),
      ],
    ),
    HelpItem(
      title: '등록 내용을 수정할 수 있나요?',
      description: '접수 중 또는 등록 완료 상태에서 수정이 가능합니다. 확인 중일 때는 수정이 제한됩니다.',
      steps: [
        HelpStep(text: '"등록 현황"에서 수정할 항목을 탭합니다.'),
        HelpStep(text: '상세 페이지에서 "수정" 버튼을 탭합니다.', assetPath: 'assets/images/prevention_registration/image3.png'),
        HelpStep(text: '내용을 수정하고 "수정완료" 버튼을 탭합니다.'),
      ],
    ),
    /**HelpItem(
      title: '등록이 반려됐어요. 어떻게 해야 하나요?',
      description: '등록이 반려된 경우 거절 사유를 확인하고 내용을 수정한 뒤 다시 신청할 수 있습니다.',
      steps: [
        HelpStep(text: '"등록 현황"에서 반려된 항목을 탭합니다.', imageLabel: '반려된 카드 – 빨간 테두리'),
        HelpStep(text: '상세 화면에서 거절 사유를 확인합니다.', imageLabel: '거절 사유 표시'),
        HelpStep(text: '"수정" 버튼을 탭하여 내용을 보완합니다.'),
        HelpStep(text: '수정 후 저장하면 재검토 요청이 자동으로 접수됩니다.'),
      ],
    ),**/
    HelpItem(
      title: '등록 완료 후 보호자 권한은 언제 생기나요?',
      description: '관리자가 예방등록을 최종 승인하면 자동으로 보호자 권한이 부여됩니다.',
      steps: [
        HelpStep(text: '담당 관리자가 등록 신청을 검토합니다.'),
        HelpStep(text: '"등록완료" 상태가 되면 보호자 계정으로 전환됩니다.'),
        HelpStep(text: '앱을 재시작하거나 재로그인하면 보호자 화면을 확인할 수 있습니다.'),
      ],
    ),
  ],
);

// ─── 5. 안전지도 ──────────────────────────────────────────────────────────────

const _catMap = HelpCategory(
  title: '안전지도',
  icon: Icons.map_outlined,
  items: [
    HelpItem(
      title: '안전지도는 어디서 볼 수 있나요?',
      description: '메인 화면 하단 탭의 "생활안전지도"를 탭하면 안전지도를 볼 수 있습니다.',
      steps: [
        HelpStep(text: '메인 화면 하단 탭에서 "생활안전지도"를 탭합니다.'),
        HelpStep(text: '현재 위치 주변의 안전 시설이 지도 위에 표시됩니다.'),
      ],
    ),
    HelpItem(
      title: '지도에 어떤 시설이 표시되나요?',
      description: '아동·노인 보호 및 안전과 관련된 시설이 표시됩니다.',
      steps: [
        HelpStep(text: '아동안전지킴이집: 아동 긴급 보호 역할을 하는 지정 가게·시설'),
        HelpStep(text: '전국보호시설: 아동·노인 보호 관련 시설'),
        HelpStep(text: '우범지역 및 공폐허가: 범죄 위험도가 높거나 방치된 지역'),
        HelpStep(text: '아동복지시설: 아동 복지 관련 시설'),
        HelpStep(text: '노인복지시설: 노인 복지 관련 시설'),
      ],
    ),
    HelpItem(
      title: '지도에 빨간 아이콘은 무엇인가요?',
      description: '빨간 아이콘은 우범지역 및 공폐허가 지역을 나타냅니다. 범죄 위험도가 높거나 방치된 지역이므로 주의가 필요합니다.',
      steps: [
        HelpStep(text: '빨간 아이콘을 탭하면 해당 지역의 상세 정보가 표시됩니다.'),
        HelpStep(text: '그 외 아이콘은 아동안전지킴이집, 보호시설, 복지시설 등 안전 관련 시설입니다.'),
      ],
    ),
    HelpItem(
      title: '현재 위치 주변 시설을 검색하려면 어떻게 하나요?',
      description: '앱이 현재 위치를 자동으로 감지하여 주변 시설을 표시합니다. 위치 권한이 필요합니다.',
      steps: [
        HelpStep(text: '안전지도를 처음 열면 현재 위치를 기준으로 자동 검색합니다.', assetPath: 'assets/images/safety_map/image1.jpg'),
        HelpStep(text: '위치가 올바르지 않으면 화면 내 "현재 위치로 이동" 버튼을 탭합니다.', assetPath: 'assets/images/safety_map/image2.jpg'),
        HelpStep(text: '위치 권한 요청이 나타나면 "허용"을 선택해 주세요.'),
      ],
    ),
    HelpItem(
      title: '"현 지도 위치로 재검색"은 무엇인가요?',
      description: '지도를 이동한 후 현재 화면에 보이는 위치를 기준으로 주변 시설을 다시 검색하는 기능입니다.',
      steps: [
        HelpStep(text: '지도를 드래그하여 검색하고 싶은 지역으로 이동합니다.', assetPath: 'assets/images/safety_map/image3.jpg'),
        HelpStep(text: '화면 상단의 "현 지도 위치로 재검색" 버튼을 탭합니다.', assetPath: 'assets/images/safety_map/image4.png'),
        HelpStep(text: '현재 화면 중심 위치를 기준으로 주변 시설이 다시 표시됩니다.'),
      ],
    ),
    HelpItem(
      title: '지도를 축소하면 시설이 사라져요.',
      description: '너무 넓은 범위를 검색하면 결과가 많아지므로, 지도 확대 수준에 따라 검색 반경이 자동으로 조정됩니다.',
      steps: [
        HelpStep(text: '지도를 더 확대(줌인)한 상태에서 "현 지도 위치로 재검색"을 탭합니다.'),
        HelpStep(text: '특정 지역을 정확히 보려면 해당 위치를 최대한 확대하고 재검색하세요.'),
      ],
    ),
    HelpItem(
      title: '시설 정보는 어떻게 확인하나요?',
      description: '지도의 마커를 탭하면 시설 이름, 주소, 연락처를 확인할 수 있습니다.',
      steps: [
        HelpStep(text: '지도 위의 마커(아이콘)를 탭합니다.', assetPath: 'assets/images/safety_map/image5.png'),
        HelpStep(text: '화면 하단에 시설 이름, 주소, 전화번호가 표시됩니다.', assetPath: 'assets/images/safety_map/image6.png'),
        HelpStep(text: '전화번호를 탭하면 바로 전화 연결이 가능합니다.'),
      ],
    ),
  ],
);

// ─── 6. 알림 ──────────────────────────────────────────────────────────────────

const _catNotification = HelpCategory(
  title: '알림',
  icon: Icons.notifications_outlined,
  items: [
    HelpItem(
      title: '어떤 경우에 알림을 받나요?',
      description: '다시봄은 다음과 같은 상황에서 알림을 전송합니다.',
      steps: [
        HelpStep(text: '신고 또는 예방등록 신청의 상태가 변경된 경우'),
        HelpStep(text: '(보호자) 피보호자의 위치 정보가 업데이트된 경우'),
        HelpStep(text: '(관리자) 새로운 신고 또는 예방등록 신청이 접수된 경우'),
        HelpStep(text: '앱 공지사항 또는 긴급 안내가 있는 경우'),
      ],
    ),
    HelpItem(
      title: '알림은 어디서 확인하나요?',
      description: '앱 내 알림 목록에서 받은 알림을 모아볼 수 있습니다.',
      steps: [
        HelpStep(text: '화면 상단의 알림 아이콘(🔔)을 탭합니다.', assetPath: 'assets/images/notifications/image1.png'),
        HelpStep(text: '수신한 알림 목록이 표시됩니다.', assetPath: 'assets/images/notifications/image2.jpg'),
        HelpStep(text: '알림을 탭하면 관련 화면으로 이동합니다.'),
      ],
    ),
    HelpItem(
      title: '알림이 오지 않아요.',
      description: '알림이 수신되지 않는 경우 아래 항목을 확인해 주세요.',
      steps: [
        HelpStep(text: '기기 설정에서 다시봄 앱의 알림 권한이 "허용"으로 설정되어 있는지 확인합니다.'),
        HelpStep(text: '인터넷 연결 상태를 확인합니다.'),
        HelpStep(text: '앱을 완전히 종료한 후 다시 실행해 보세요.'),
        HelpStep(text: '문제가 지속되면 로그아웃 후 다시 로그인해 보세요.'),
      ],
    ),
  ],
);

// ─── 7. 보호자 기능 ───────────────────────────────────────────────────────────

const _catGuardian = HelpCategory(
  title: '보호자 기능',
  icon: Icons.shield_outlined,
  roles: ['guardian'],
  items: [
    HelpItem(
      title: '보호자 화면은 어떻게 구성되어 있나요?',
      description: '보호자 계정으로 로그인하면 홈 화면이 보호자 전용 화면으로 표시됩니다.',
      steps: [
        HelpStep(text: '상단 카드 영역: 등록된 피보호자 목록이 카드 형태로 표시됩니다.'),
        HelpStep(text: '피보호자 프로필: 카드를 탭하면 상세 정보를 볼 수 있습니다.'),
        HelpStep(text: '실시간 위치 지도: 선택된 피보호자의 현재 위치가 지도에 표시됩니다.'),
      ],
    ),
    HelpItem(
      title: '피보호자 정보는 어디서 확인하나요?',
      description: '보호자 계정으로 로그인하면 홈 화면에서 피보호자 카드를 바로 확인할 수 있습니다.',
      steps: [
        HelpStep(text: '보호자 계정으로 로그인합니다.'),
        HelpStep(text: '홈 화면 상단의 피보호자 카드에서 이름, 사진, 기본 정보를 확인합니다.'),
        HelpStep(text: '카드를 탭하면 상세 프로필을 볼 수 있습니다.'),
      ],
    ),
    HelpItem(
      title: '피보호자가 여러 명이면 어떻게 선택하나요?',
      description: '홈 화면 상단 카드를 좌우로 슬라이드하여 다른 피보호자를 선택할 수 있습니다.',
      steps: [
        HelpStep(text: '홈 화면 피보호자 카드를 좌우로 슬라이드합니다.'),
        HelpStep(text: '원하는 피보호자 카드에서 멈추면 해당 피보호자의 정보와 위치가 표시됩니다.'),
        HelpStep(text: '카드 하단의 점(인디케이터)으로 현재 몇 번째 피보호자인지 확인할 수 있습니다.'),
      ],
    ),
    HelpItem(
      title: '피보호자의 현재 위치는 어떻게 확인하나요?',
      description: '등록이 완료되고 뱃지가 연결된 피보호자는 보호자 홈에서 실시간 위치를 확인할 수 있습니다.',
      steps: [
        HelpStep(text: '보호자 계정으로 로그인합니다.'),
        HelpStep(text: '상단 피보호자 카드에서 위치를 확인할 피보호자를 선택합니다.'),
        HelpStep(text: '카드 아래 지도에서 피보호자의 현재 위치(빨간 점)를 확인합니다.', assetPath: 'assets/images/guardian_features/image1.png'),
        HelpStep(text: '여러 명이 등록된 경우 카드를 좌우로 이동하여 피보호자를 전환합니다.'),
      ],
    ),
    HelpItem(
      title: '위치는 얼마나 자주 업데이트되나요?',
      description: '피보호자의 위치는 뱃지에서 GPS 신호를 전송할 때마다 실시간으로 업데이트됩니다.',
      steps: [
        HelpStep(text: '뱃지가 GPS 신호를 수신하는 실외 환경에서 가장 정확한 위치가 표시됩니다.'),
        HelpStep(text: '실내이거나 GPS 신호가 약한 경우 마지막으로 수신된 위치가 표시될 수 있습니다.'),
        HelpStep(text: '위치 갱신이 오래된 경우 지도 새로고침 버튼을 탭하세요.'),
      ],
    ),
    HelpItem(
      title: '뱃지 위치가 표시되지 않아요.',
      description: '뱃지 위치가 지도에 표시되지 않는 경우 아래 항목을 순서대로 확인해 주세요.',
      steps: [
        HelpStep(text: '피보호자 등록이 "등록완료" 상태인지 확인합니다.'),
        HelpStep(text: '뱃지가 피보호자에게 올바르게 착용되어 있는지 확인합니다.'),
        HelpStep(text: '뱃지가 GPS 신호를 수신할 수 있는 실외에 있는지 확인합니다.'),
        HelpStep(text: '앱을 완전히 종료한 후 다시 실행해 보세요.'),
        HelpStep(text: '문제가 지속되면 관리자에게 문의해 주세요.'),
      ],
    ),
    HelpItem(
      title: '피보호자가 실종된 것 같아요. 어떻게 해야 하나요?',
      description: '피보호자의 위치가 확인되지 않거나 이상한 경우 즉시 신고해 주세요.',
      steps: [
        HelpStep(text: '보호자 홈에서 피보호자의 마지막 위치를 확인합니다.'),
        HelpStep(text: '즉시 112(경찰)에 실종 신고를 합니다.'),
        HelpStep(text: '"신고·제보" 탭에서 실종 신고를 접수합니다.', assetPath: 'assets/images/guardian_features/image2.jpg'),
        HelpStep(text: '신고 시 뱃지의 마지막 확인 위치 정보를 함께 전달하면 도움이 됩니다.'),
      ],
    ),
  ],
);

// ─── 8. 관리자 기능 ───────────────────────────────────────────────────────────

const _catAdmin = HelpCategory(
  title: '관리자 기능',
  icon: Icons.admin_panel_settings_outlined,
  roles: ['admin'],
  items: [
    HelpItem(
      title: '관리자 화면은 일반 회원과 무엇이 다른가요?',
      description: '관리자 계정으로 로그인하면 일반 사용자의 신고 및 예방등록 신청 전체를 관리할 수 있습니다.',
      steps: [
        HelpStep(text: '"신고 현황"에서 모든 사용자의 신고 목록이 표시됩니다.'),
        HelpStep(text: '"등록 현황"에서 모든 예방등록 신청 목록이 표시됩니다.'),
        HelpStep(text: '각 항목에서 상태 변경(승인·반려)이 가능합니다.'),
        HelpStep(text: '신청자 이름이 카드 하단에 추가로 표시됩니다.', assetPath: 'assets/images/admin_features/image1.png'),
      ],
    ),
    HelpItem(
      title: '실종 신고는 어떻게 검토하나요?',
      description: '관리자 계정으로 접속하면 신고 목록을 확인하고 각 신고의 상태를 변경할 수 있습니다.',
      steps: [
        HelpStep(text: '관리자 계정으로 로그인합니다.'),
        HelpStep(text: '"신고·제보" 탭 → "신고 현황"에서 신고 목록을 확인합니다.', assetPath: 'assets/images/admin_features/image2.jpg'),
        HelpStep(text: '검토할 신고 카드를 탭하여 상세 내용을 확인합니다.'),
        HelpStep(text: '하단의 "수정하기" 버튼을 누른 뒤 원하는 상태("확인 중", "신고완료" 등)를 선택하고 "수정완료" 버튼을 눌러 저장합니다.', assetPath: 'assets/images/admin_features/image3.png'),
      ],
    ),
    HelpItem(
      title: '실종예방등록은 어떻게 승인하나요?',
      description: '등록 현황에서 신청 내용을 검토한 후 승인하면 해당 사용자에게 보호자 권한이 부여됩니다.',
      steps: [
        HelpStep(text: '하단 탭에서 "실종예방등록"을 탭합니다.'),
        HelpStep(text: '"등록 현황" 탭에서 신청 목록을 확인합니다.'),
        HelpStep(text: '승인할 항목을 탭합니다.'),
        HelpStep(text: '사진 검증 결과와 신청 내용을 검토합니다.'),
        HelpStep(text: '상태를 "확인중" → "등록완료"로 변경하면 신청자에게 보호자 권한이 부여됩니다.'),
      ],
    ),
    HelpItem(
      title: '사진 검증 결과는 어떻게 확인하나요?',
      description: '예방등록 상세 화면에서 등록된 각 사진의 검증 결과를 확인할 수 있습니다.',
      steps: [
        HelpStep(text: '등록 현황에서 해당 항목을 탭합니다.'),
        HelpStep(text: '상세 화면의 사진 영역에서 각 사진 아래 검증 상태(정상·경고·오류)를 확인합니다.', assetPath: 'assets/images/admin_features/image4.png'),
        HelpStep(text: '카드 목록에서도 요약 정보(총 장수·정상·경고·오류 수)를 확인할 수 있습니다.', assetPath: 'assets/images/admin_features/image5.png'),
        HelpStep(text: '오류 사진이 많은 경우 반려 후 재등록을 요청하세요.'),
      ],
    ),
    HelpItem(
      title: '신청을 반려하려면 어떻게 하나요?',
      description: '등록 상세 화면에서 상태를 "거절"로 변경하고 사유를 입력하면 신청자 화면에 거절 사유가 표시됩니다.',
      steps: [
        HelpStep(text: '등록 상세 화면에서 상태를 "거절"로 선택합니다.', assetPath: 'assets/images/admin_features/image6.png'),
        HelpStep(text: '거절 사유를 입력합니다. 신청자에게 그대로 표시됩니다.'),
        HelpStep(text: '"수정완료" 버튼을 탭합니다.'),
        HelpStep(text: '신청자는 거절 사유를 확인하고 내용을 수정하여 재신청할 수 있습니다.'),
      ],
    ),
    HelpItem(
      title: '피보호자 뱃지 일련번호는 어디서 확인하나요?',
      description: '등록 상세 페이지 하단의 뱃지 정보 섹션에서 일련번호를 확인할 수 있습니다.',
      steps: [
        HelpStep(text: '"등록 현황"에서 해당 피보호자 항목을 탭합니다.'),
        HelpStep(text: '상세 페이지를 아래로 스크롤합니다.'),
        HelpStep(text: '"뱃지 정보 (관리자)" 섹션에서 뱃지 일련번호를 확인합니다.', assetPath: 'assets/images/admin_features/image7.png'),
        HelpStep(text: '일련번호가 "정보 없음"으로 표시될 경우 아직 뱃지가 연결되지 않은 상태입니다.'),
      ],
    ),
  ],
);

// ─── 검색 결과 래퍼 ────────────────────────────────────────────────────────────

class _SearchResult {
  final HelpCategory category;
  final HelpItem item;
  _SearchResult(this.category, this.item);
}

// ─── HelpPage 위젯 ─────────────────────────────────────────────────────────────

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _role = '';
  String _searchQuery = '';
  final Map<int, bool> _expanded = {};
  bool _roleLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _role = prefs.getString('role') ?? '';
      _roleLoaded = true;
    });
  }

  List<HelpCategory> get _categories {
    final all = [
      _catStart,
      _catMissing,
      _catReport,
      _catRegister,
      _catMap,
      _catNotification,
      _catGuardian,
      _catAdmin,
    ];
    return all.where((c) => c.roles.isEmpty || c.roles.contains(_role)).toList();
  }

  List<_SearchResult> get _searchResults {
    final q = _searchQuery.toLowerCase();
    final results = <_SearchResult>[];
    for (final cat in _categories) {
      for (final item in cat.items) {
        if (item.title.toLowerCase().contains(q) ||
            item.description.toLowerCase().contains(q)) {
          results.add(_SearchResult(cat, item));
        }
      }
    }
    return results;
  }

  void _openDetail(HelpItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HelpDetailPage(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('도움말', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (!_roleLoaded)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: _searchQuery.isNotEmpty
                  ? _buildSearchResults()
                  : _buildCategoryList(),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: '궁금한 내용을 검색해 보세요',
          hintStyle: const TextStyle(fontSize: 14, color: Colors.black38),
          prefixIcon: const Icon(Icons.search, color: Colors.black38, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: Colors.black38),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF2F2F2),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    final cats = _categories;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      itemCount: cats.length,
      itemBuilder: (context, i) => _buildCategorySection(cats[i], i),
    );
  }

  Widget _buildCategorySection(HelpCategory cat, int catIndex) {
    final isExpanded = _expanded[catIndex] ?? false;
    const maxPreview = 4;
    final showToggle = cat.items.length > maxPreview;
    final displayItems =
        isExpanded || !showToggle ? cat.items : cat.items.take(maxPreview).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                Icon(cat.icon, size: 20, color: const Color(0xFFD4930A)),
                const SizedBox(width: 8),
                Text(
                  cat.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFEEEEEE)),
          ...displayItems.map((item) => _buildItemTile(item)),
          if (showToggle)
            InkWell(
              onTap: () => setState(() => _expanded[catIndex] = !isExpanded),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: const BoxDecoration(
                  color: Color(0xFFFDF9EB),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Text(
                  isExpanded ? '접기 △' : '전체 ${cat.items.length}개 보기 〉',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFD4930A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemTile(HelpItem item) {
    return InkWell(
      onTap: () => _openDetail(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 13, color: Colors.black38),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = _searchResults;
    if (results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 52, color: Colors.black26),
            SizedBox(height: 12),
            Text('검색 결과가 없습니다.', style: TextStyle(fontSize: 15, color: Colors.black45)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final r = results[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: Text(r.item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(r.category.title, style: const TextStyle(fontSize: 12, color: Colors.black45)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 13, color: Colors.black38),
            onTap: () => _openDetail(r.item),
          ),
        );
      },
    );
  }
}
