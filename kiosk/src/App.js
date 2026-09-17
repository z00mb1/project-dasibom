import React, { useState, useEffect, useCallback, useRef } from 'react';
import './App.css';

// 기본 프로필 아이콘 (사진 없을 때 표시)
const DefaultProfile = ({ size = '100%' }) => (
  <svg
    width={size} height={size}
    viewBox="0 0 100 100"
    xmlns="http://www.w3.org/2000/svg"
    style={{ display: 'block' }}
  >
    <rect width="100" height="100" fill="#e0e0e0" />
    <circle cx="50" cy="38" r="18" fill="#bdbdbd" />
    <ellipse cx="50" cy="80" rx="28" ry="20" fill="#bdbdbd" />
  </svg>
);

// 백엔드 주소. Render 에 올라가 있고 CORS 가 모든 오리진에 열려 있어서 페이지가 직접 부른다.
//
// 예전에는 zrok 무료 터널을 썼다. 그 터널은 브라우저에서 온 요청에 데이터 대신 경고
// HTML 을 돌려주고 CORS 헤더도 안 붙여서, 우회 헤더를 대신 붙여 줄 같은 오리진 프록시
// (api/proxy.js)를 한 단계 끼워야 했다. Render 로 옮기면서 그 이유가 사라져 걷어냈다.
//
// 직접 부르는 편이 콜드 스타트에도 강하다. Render 무료 플랜은 15분 놀면 잠들고 첫 요청이
// 최대 50초 걸리는데, 서버리스 함수는 그 전에 끊기지만 브라우저 fetch 는 기다려 준다.
const BASE_URL = process.env.REACT_APP_API_BASE || 'https://dasibom-m9c3.onrender.com';

// 사진은 백엔드가 아니라 Cloudinary CDN 주소로 내려온다.
// (예전에는 백엔드 자기 /media/ 절대주소여서 호스트를 프록시 주소로 갈아끼워야 했다)
// 이제 그대로 쓰면 되지만, http 로 내려오는 값이 섞이면 https 페이지에서 <img> 가
// 혼합 콘텐츠로 차단되므로 프로토콜만 올려 준다.
const toPhotoUrl = (url) =>
  typeof url === 'string' ? url.replace(/^http:\/\//, 'https://') : url;

// 사진이 없거나, 주소는 있는데 실제로 못 불러온 경우 기본 아이콘으로 대체한다.
// (예전에는 주소만 있으면 무조건 <img> 를 그려서, 실패하면 빈 칸으로 남았다)
const Photo = ({ src, className }) => {
  const [failed, setFailed] = useState(false);
  useEffect(() => { setFailed(false); }, [src]); // 다른 사람으로 바뀌면 다시 시도
  if (!src || src === '/profile.png' || failed) return <DefaultProfile />;
  return <img src={src} className={className} alt="" onError={() => setFailed(true)} />;
};

// 키오스크 기기에서 돌아가는 NFC 서버(nfc_server.py) 주소.
// 배포된 페이지에서도 키오스크 본체의 리더기를 직접 호출한다.
const NFC_URL = process.env.REACT_APP_NFC_URL || "http://127.0.0.1:5000";
// 이 키오스크 자체의 ID. 긴급신고와 위치공유를 어느 키오스크에서 보냈는지
// 백엔드에 알리는 데 쓴다. 기기마다 다르게 넣는다.
//
// 키링(GPS)의 ID 와는 다른 것이다. 키링 좌표는 아래 KEYRING_BY_BADGE 로 찾는다.
// 예전에는 이 값 하나로 키링 좌표까지 조회해서, 누가 태그하든 항상 1호 키링
// 좌표가 보호자에게 갔다.
const DEVICE_ID = process.env.REACT_APP_DEVICE_ID || "KIOSK_001";

// 리더기가 주는 UID 는 소문자 16진수(구분자 없음)다. 서버도 같은 정규화를 하지만,
// 리더기 쪽 구현이 바뀌어도 서버에 늘 같은 모양으로 보내도록 여기서도 맞춰 준다.
export const normalizeBadgeUid = (uid) =>
  typeof uid === 'string' ? uid.toLowerCase().replace(/[^0-9a-f]/g, '') : '';

// 스티커가 어느 키링 것인지는 서버가 안다. 태그하면 UID 하나만 보내고
// GET /dasibom/gps/latest/?badge_uid=... 로 그 키링의 좌표를 받아온다.
//
// 예전에는 이 파일 안에 UID -> device_code 대조표를 두고 먼저 걸렀다. 백엔드에
// 조회가 없던 동안의 임시 배선이었는데, 키링을 늘릴 때마다 다시 빌드해야 했고
// 서버 쪽 매핑과 어긋나면 남의 키링 좌표를 보내게 되어 걷어냈다.
//
// 등록되지 않은 카드는 서버가 404 + "등록되지 않은 뱃지입니다." 로 알려준다.

// [현재위치공유] 백엔드가 돌려준 좌표를 믿어도 되는지 판정하는 기준.
//
// 예전에는 `lat && lng` 만 보고 값이 있으면 무조건 "GPS 받음" 으로 쳤다. 그런데 이 값은
// 키오스크가 방금 잰 위치가 아니라 서버 DB 에 남아 있는 마지막 기록이라, 한 번 아무 값이나
// 들어가면 그 뒤로는 영원히 참이 된다. 실제로 배포된 키오스크는 위치를 한 번도 받은 적이
// 없는데도 서울시청 좌표(37.5665, 126.9780 - 지도 예제의 기본값)를 계속 돌려받아서,
// 버튼이 노랗게 켜진 채 보호자에게 엉뚱한 곳을 보내고 있었다.
//
// 더군다나 이 값은 공유 버튼이 POST 하는 값과 같은 곳에 쌓이는 것으로 보인다. 읽은 값을
// 그대로 다시 써서 스스로를 되살리는 고리라, 시각만 검사하면 누를 때마다 다시 켜진다.
// 그래서 시각뿐 아니라 값 자체도 같이 검사한다.
//
// 길 잃은 사람을 찾으라고 보내는 좌표다. 틀린 좌표는 좌표가 없는 것보다 나쁘다.
const GPS_MAX_AGE_MS = 300000; // 5분. 이보다 오래된 기록은 "지금 위치" 가 아니다.

// 지도 라이브러리 예제와 시드 데이터에 흔히 박혀 있는 자리표시자 좌표.
// 실측값이 우연히 소수점 4자리까지 여기 맞을 일은 없으므로 좌표 없음으로 친다.
const PLACEHOLDER_COORDS = [
  { lat: 37.5665, lng: 126.9780 }, // 서울시청. 카카오/네이버 지도 예제의 기본 중심
  { lat: 0, lng: 0 },              // 값이 비었을 때 흔히 저장되는 좌표
];

// 믿을 수 있는 좌표면 {lat, lng}, 아니면 null 을 돌려준다.
// null 이면 공유 버튼은 회색으로 잠긴다.
export const readTrustworthyGps = (data) => {
  const reject = (reason) => {
    // 키오스크 현장에서 버튼이 왜 잠겼는지 콘솔로 확인할 수 있게 남긴다.
    console.warn(`[위치공유] 좌표를 쓰지 않음: ${reason}`, data);
    return null;
  };
  if (!data || data.lat == null || data.lng == null) return reject('좌표가 응답에 없음');

  const lat = Number(data.lat);
  const lng = Number(data.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return reject('좌표가 숫자가 아님');
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return reject('좌표 범위를 벗어남');
  // 빈 문자열은 Number('') 이 0 이 되어 아래 (0, 0) 검사에서 걸러진다.
  if (PLACEHOLDER_COORDS.some(p => Math.abs(p.lat - lat) < 1e-4 && Math.abs(p.lng - lng) < 1e-4)) {
    return reject('실측값이 아니라 자리표시자 좌표');
  }

  // 언제 잰 값인지 모르면 지금 위치라고 볼 근거가 없다.
  const measuredAt = Date.parse(data.timestamp);
  if (!Number.isFinite(measuredAt)) return reject('측정 시각이 없거나 읽을 수 없음');
  const age = Date.now() - measuredAt;
  if (age > GPS_MAX_AGE_MS) return reject(`${Math.round(age / 60000)}분 전 기록이라 너무 오래됨`);
  // 서버 시계가 앞서 있으면 미래 시각이 올 수 있다. 조금은 봐주되 터무니없으면 거른다.
  if (age < -GPS_MAX_AGE_MS) return reject('측정 시각이 미래');

  return { lat, lng };
};
const categories = ['전체', '장애', '치매', '아동', '기타'];
const regions = [
  '전체', '서울', '경기', '인천', '강원',
  '충북', '충남', '대전', '세종',
  '경북', '경남', '대구', '부산', '울산',
  '전북', '전남', '광주', '제주',
];

// 실종자 정보 화면의 두 탭. 왼쪽이 기본 탭이다.
// 찾는 중 = 가족이 찾고 있는 실종자, 보호 중 = 기관이 보호하면서 가족을 찾는 사람.
export const LIST_TABS = [
  { key: 'finding', label: '찾는 중이에요', path: 'missingperson/cards/' },
  { key: 'protecting', label: '보호 중이에요', path: 'protectedperson/cards/' },
];

// 서버의 sido 필터는 발생 장소 주소에 그 글자가 들어 있는지만 본다. 그런데 주소는
// "경북 경주시" 와 "경상북도 문경시" 가 섞여 들어와서, "경북" 으로만 물으면 정식 명칭으로
// 적힌 사람이 어느 지역에도 안 나온다. 2026-09-14 기준 찾는 중 46명, 보호 중 57명이
// 이렇게 빠졌다. 약칭과 정식 명칭으로 각각 물어 합친다.
// (강원도/강원특별자치도, 전북특별자치도 는 약칭이 이미 들어 있어 따로 안 적는다)
const REGION_ALIASES = {
  충북: ['충북', '충청북도'],
  충남: ['충남', '충청남도'],
  경북: ['경북', '경상북도'],
  경남: ['경남', '경상남도'],
  전북: ['전북', '전라북도'],
  전남: ['전남', '전라남도'],
};

// 서버에 보낼 sido 값 목록. '전체' 면 필터 없이 한 번만 부른다.
export const regionQueries = (region) =>
  region === '전체' ? [null] : (REGION_ALIASES[region] || [region]);

// 찾는 중은 "2026-09-14", 보호 중은 "2026.03.17" 로 내려온다. 한 모양으로 맞춘다.
const toDateText = (date) => (typeof date === 'string' ? date.replace(/\./g, '-') : '');

// 선택한 탭과 지역의 카드 목록을 받아온다.
//
// 분류(장애/치매...)는 여기서 서버에 보내지 않고 화면에서 거른다. 서버의 category 필터는
// 저장된 원본 값과 똑같아야 걸리는데, 찾는 중에는 원본이 "치매환자" 인 사람이 섞여 있다.
// 이 사람들은 카드 태그에는 "치매" 로 나오면서 치매 필터에서는 빠졌다.
export const fetchPersonCards = async (tabKey, region, signal) => {
  const { path } = LIST_TABS.find(t => t.key === tabKey);
  const lists = await Promise.all(regionQueries(region).map(async (sido) => {
    const query = sido ? `?sido=${encodeURIComponent(sido)}` : '';
    const res = await fetch(`${BASE_URL}/dasibom/${path}${query}`, { signal });
    if (!res.ok) throw new Error(`서버 응답 오류 (HTTP ${res.status})`);
    return res.json();
  }));

  // 주소에 약칭과 정식 명칭이 둘 다 들어 있으면 두 번 걸리므로 한 번만 남긴다
  const seen = new Set();
  const persons = lists.flat()
    .filter(item => !seen.has(item.id) && seen.add(item.id))
    .map(item => ({
      id: item.id, type: item.category_display,
      img: toPhotoUrl(item.photo) || '/profile.png', name: item.name,
      gender: item.gender_display, age: item.current_age,
      registeredDate: toDateText(item.registered_date),
    }));

  // 한 번만 불렀으면 서버 순서를 그대로 둔다. 여러 번 불러 이어 붙였으면 약칭 쪽이
  // 전부 앞에 오게 되므로 등록일 최신순으로 다시 세운다. (같은 날짜끼리는 순서 유지)
  if (lists.length > 1) {
    persons.sort((a, b) => b.registeredDate.localeCompare(a.registeredDate));
  }
  return persons;
};

// 무인 자동 초기화.
// 태그한 사람이 자리를 떠도 화면이 그대로 남아 있으면 다음 사람이
// 그 상태를 물려받아 남의 위치를 공유할 수 있으므로 시간이 지나면 되돌린다.
// 어르신이 실종자 목록을 천천히 읽는 중에 화면이 갑자기 튕기지 않도록
// 곧바로 초기화하지 않고 경고를 먼저 띄운다.
const IDLE_WARN_MS = 90000;   // 조작이 없으면 이만큼 뒤에 경고를 띄우고
const IDLE_RESET_MS = 10000;  // 경고 후 이만큼 더 지나면 처음 화면으로

// 리더기 호출이 실패했을 때 태그 대기 화면에 띄울 안내 문구.
// https 로 배포된 페이지가 http://127.0.0.1 을 부르는 구성은 크롬 142 부터
// "로컬 네트워크 접근" 권한 없이는 아예 차단되므로 그 경우를 따로 알려준다.
// 백엔드 호출이 실패했을 때 화면에 띄울 문구.
// 서버가 죽었는지 키오스크 인터넷이 끊겼는지는 브라우저가 구분해 주지 않으므로
// 확인할 곳을 같이 적어준다.
//
// Render 무료 플랜의 콜드 스타트(최대 50초)는 여기 걸리지 않는다. 그동안 fetch 는
// 실패하는 게 아니라 그냥 기다리므로 화면에는 로딩이 길어지는 것으로만 보인다.
const describeApiError = (err) => {
  if (err instanceof TypeError) {
    return `서버(${BASE_URL})에 연결하지 못했습니다. 키오스크 인터넷 연결과 백엔드 상태를 확인하세요.`;
  }
  return `정보를 불러오지 못했습니다. (${err.message})`;
};

const describeNfcError = (err) => {
  // fetch 가 응답 자체를 못 받으면 TypeError(Failed to fetch)가 난다.
  // 차단당했는지 서버가 꺼졌는지는 브라우저가 구분해 주지 않는다.
  if (!(err instanceof TypeError)) return err.message;
  const mayBeBlocked =
    window.location.protocol === 'https:' && NFC_URL.startsWith('http://');
  return mayBeBlocked
    ? `리더기(${NFC_URL})에 연결하지 못했습니다. 브라우저가 로컬 리더기 접근을 막았거나 리더기 서버가 꺼져 있습니다.`
    : `리더기(${NFC_URL})에 연결하지 못했습니다. nfc_server.py 가 켜져 있는지 확인하세요.`;
};

// 안전 지도를 열면 처음 보여줄 곳. 중부대학교 고양캠퍼스(경기 고양시 덕양구 동헌로 305).
// 좌표는 OpenStreetMap 의 캠퍼스 위치다. 예전 값(37.7093, 126.8524)은 캠퍼스에서
// 서쪽으로 3.4km 떨어진 관산동 통일로 위였다.
const MAP_START = { lat: 37.7132095, lng: 126.8904235 };
const MAP_START_LEVEL = 3; // 카카오맵 확대 단계. 숫자가 작을수록 가깝게 보인다

function App() {
  const [screen, setScreen] = useState('start');
  const [isTagged, setIsTagged] = useState(false);
  const [currentSlide, setCurrentSlide] = useState(0);
  const [selectedCategory, setSelectedCategory] = useState('전체');
  const [selectedRegion, setSelectedRegion] = useState('전체');
  // 실종자 정보 화면의 탭. 'finding'(찾는 중이에요) 또는 'protecting'(보호 중이에요)
  const [listTab, setListTab] = useState('finding');
  const listScrollRef = useRef(null);
  // currentAddress는 아직 화면에 표시하지 않지만 재검색 시 주소를 갱신해 둔다
  // eslint-disable-next-line no-unused-vars
  const [currentAddress, setCurrentAddress] = useState("");

  const [mapInstance, setMapInstance] = useState(null);
  const [slides, setSlides] = useState([]);
  const [personList, setPersonList] = useState([]);
  const [isLoading, setIsLoading] = useState(false);

  const markersRef = useRef([]);
  const mapContainerRef = useRef(null);
  const mapInfoRef = useRef(null); // 지도 아래쪽을 덮는 주소/전화번호 칸
  const videoRef = useRef(null);
  const [selectedFacility, setSelectedFacility] = useState(null);
  const [taggedGpsData, setTaggedGpsData] = useState(null); // 태깅 시점에 저장된 GPS // 클릭한 시설 정보
  // 리더기 호출이 실패한 이유. null 이면 정상 통신 중.
  const [nfcError, setNfcError] = useState(null);
  // 등록되지 않은 카드를 댔을 때의 안내. 리더기 오류와 따로 관리한다.
  // (nfcError 는 폴링이 성공할 때마다 지워지므로 여기 섞으면 1초 만에 사라진다)
  const [badgeError, setBadgeError] = useState(null);
  // 백엔드 호출이 실패한 이유. 화면마다 따로 보여준다.
  const [slidesError, setSlidesError] = useState(null);
  const [listError, setListError] = useState(null);

  // 자동 초기화 경고. null 이면 경고 없음, 숫자면 초기화까지 남은 초.
  const [idleCountdown, setIdleCountdown] = useState(null);
  // 경고 모달의 "계속하기" 버튼이 타이머를 되감을 수 있도록 최신 함수를 담아둔다
  const rescheduleIdleRef = useRef(() => {});

  // 태그 한 건마다 올라가는 번호. GPS 응답은 늦게 도착할 수 있는데, 그 사이
  // 화면이 초기화됐거나 다음 사람이 태그했으면 그 응답을 버려야 한다.
  // 안 그러면 앞사람 좌표가 뒷사람 화면에 얹혀 남의 위치가 공유된다.
  const tagSessionRef = useRef(0);

  // [기능 1] 홈 화면 슬라이드 데이터 로딩
  useEffect(() => {
    const fetchMissingPersons = async () => {
      try {
        const [recentRes, longTermRes] = await Promise.all([
          fetch(`${BASE_URL}/dasibom/missingperson/recent/`),
          fetch(`${BASE_URL}/dasibom/missingperson/long-term/`)
        ]);
        if (!recentRes.ok || !longTermRes.ok) {
          throw new Error(`서버 응답 오류 (HTTP ${recentRes.status}/${longTermRes.status})`);
        }
        const recentData = await recentRes.json();
        const longTermData = await longTermRes.json();
        const combined = [
          ...recentData.map(item => ({ ...item, type: '단기 실종' })),
          ...longTermData.map(item => ({ ...item, type: '장기 실종' }))
        ].map(item => ({
          id: item.id, name: item.name, age: item.current_age,
          gender: item.gender_display, category: item.category_display,
          type: item.type, img: toPhotoUrl(item.photo) || '/profile.png'
        }));
        setSlides(combined);
        setSlidesError(null);
      } catch (error) {
        // 예전에는 콘솔에만 찍혀서 화면에는 "데이터 로딩 중..."이 영원히 남았다
        console.error("슬라이드 로드 실패:", error);
        setSlidesError(describeApiError(error));
      }
    };
    fetchMissingPersons();
  }, []);

  // [기능 2] 슬라이드 자동 재생
  useEffect(() => {
    if (screen === 'start' && slides.length > 0) {
      const timer = setInterval(() => {
        setCurrentSlide((prev) => (prev + 1) % slides.length);
      }, 10000);
      return () => clearInterval(timer);
    }
  }, [screen, slides]);

  // [기능 3] 웹캠 스트림 시작
  useEffect(() => {
    let currentStream = null;
    const startCamera = async () => {
      try {
        // facingMode 제거 - PC 외부 웹캠(앱코 APC930 등) 자동 인식
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { width: { ideal: 1280 }, height: { ideal: 720 } },
          audio: false
        });
        currentStream = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          // autoPlay 속성으로 재생되므로 play() 직접 호출 제거
        }
      } catch (err) {
        console.error('웹캠 연결 실패:', err);
      }
    };
    startCamera();
    return () => {
      if (currentStream) currentStream.getTracks().forEach(track => track.stop());
    };
  }, []);

  // [기능 4] 실종자 목록 조회 - 탭(찾는 중/보호 중)과 지역이 바뀔 때마다 다시 받는다
  //
  // 예전에는 탭 없이 보호 중 목록(protectedperson)만 불렀다.
  useEffect(() => {
    if (screen !== 'detail') return;

    // 탭을 빠르게 바꾸면 앞 탭의 응답이 뒤늦게 도착할 수 있다. Render 콜드 스타트면
    // 수십 초 차이도 난다. 그대로 두면 보호 중 탭에 찾는 중인 사람이 덮어써지므로
    // 조건이 바뀌면 앞 요청을 끊는다.
    const controller = new AbortController();
    setIsLoading(true);
    setPersonList([]);
    setListError(null);

    fetchPersonCards(listTab, selectedRegion, controller.signal)
      .then(setPersonList)
      .catch((error) => {
        if (error.name === 'AbortError') return;
        console.error("실종자 목록 로드 실패:", error);
        setListError(describeApiError(error));
      })
      .finally(() => {
        if (!controller.signal.aborted) setIsLoading(false);
      });

    return () => controller.abort();
  }, [screen, listTab, selectedRegion]);

  // 조건을 바꾸면 목록을 맨 위부터 보여준다. 안 그러면 앞 목록에서 내려간 만큼
  // 새 목록도 중간부터 보여서 앞쪽 사람을 못 보고 지나친다.
  useEffect(() => {
    if (listScrollRef.current) listScrollRef.current.scrollTop = 0;
  }, [listTab, selectedRegion, selectedCategory]);

  // 분류는 서버에 묻지 않고 카드 태그 기준으로 거른다 (fetchPersonCards 주석 참고)
  const visiblePersons = selectedCategory === '전체'
    ? personList
    : personList.filter(person => person.type === selectedCategory);

  // [기능 5] NFC 태그 감지 폴링 (tagWait 화면일 때만 작동)
  useEffect(() => {
    let checkNfc = null;
    if (screen === 'tagWait') {
      setNfcError(null);
      // badgeError 는 여기서 지우지 않는다. 등록 안 된 카드였을 때 이 화면으로
      // 되돌리면서 안내를 띄우는데, 여기서 지우면 그 안내가 바로 사라진다.
      // 대신 태그가 성공했을 때와 화면을 떠날 때 지운다.
      const poll = () => {
        fetch(`${NFC_URL}/check`)
          .then(res => {
            if (!res.ok) throw new Error(`리더기 서버가 오류를 반환했습니다 (HTTP ${res.status})`);
            return res.json();
          })
          .then(async data => {
            setNfcError(null);
            if (data.status === 'success') {
              const badgeUid = normalizeBadgeUid(data.uid);
              if (!badgeUid) {
                // 리더기가 태그는 잡았는데 UID 를 못 준 경우. 서버에 물어볼 것이 없다.
                console.warn('[뱃지] 리더기가 UID 를 주지 않았다', data);
                setBadgeError('뱃지 번호를 읽지 못했습니다. 다시 대주세요.');
                return;
              }
              setBadgeError(null);

              const session = ++tagSessionRef.current;

              // 앞사람 좌표를 물려주지 않도록 먼저 비운다.
              // 공유 버튼은 이번 좌표가 도착할 때까지 회색으로 잠겨 있다.
              setTaggedGpsData(null);
              setIsTagged(true);
              setScreen('tagDone');

              // GPS 조회는 화면 전환을 기다리게 하지 않는다.
              // 예전에는 이 응답을 받고 나서야 화면을 넘겼다. 그런데 Render 무료 플랜은
              // 15분 놀면 잠들고 첫 요청에 최대 50초가 걸린다. 그동안 화면에는
              // "키링을 대주세요"가 그대로 떠 있어 태그가 안 먹은 것처럼 보였고,
              // 그 사이 "돌아가기"를 누르면 뒤늦게 tagDone 으로 끌려갔다.
              //
              // 이 스티커가 등록된 것인지와 그 키링의 최신 좌표를 한 번에 받아온다.
              // 값이 있다고 바로 쓰지 않고 readTrustworthyGps 로 걸러낸다.
              // 믿을 수 없는 값은 null 로 남아 공유 버튼이 회색으로 잠긴다.
              try {
                const gpsRes = await fetch(
                  `${BASE_URL}/dasibom/gps/latest/?badge_uid=${encodeURIComponent(badgeUid)}`
                );
                const payload = await gpsRes.json().catch(() => null);
                // 기다리는 동안 초기화됐거나 다음 사람이 태그했으면 이 응답은 버린다
                if (tagSessionRef.current !== session) return;

                if (gpsRes.ok) {
                  setTaggedGpsData(readTrustworthyGps(payload));
                  return;
                }

                // 등록 안 된 뱃지와 "아직 좌표 기록이 없음" 은 둘 다 404 로 오고
                // 문구로만 갈린다. 서버가 문구를 바꾸면 아래 판정이 헐거워지는데,
                // 그때는 등록 안 된 카드가 태그 완료 화면에 남을 뿐이다. 좌표는
                // 없으므로 공유 버튼은 회색 그대로여서 위험하지는 않다.
                const message = (payload && payload.message) || '';
                if (gpsRes.status === 404 && message.includes('등록')) {
                  console.warn(`[뱃지] 등록되지 않은 UID: ${badgeUid}`);
                  setIsTagged(false);
                  setBadgeError(`등록되지 않은 카드입니다. 키링을 대주세요. (${badgeUid})`);
                  setScreen('tagWait');
                  return;
                }
                console.warn(`[위치공유] GPS 조회 실패 (HTTP ${gpsRes.status}) ${message}`);
              } catch (err) {
                console.error('태깅 시 GPS 수신 실패:', err);
              }
            }
          })
          .catch(err => {
            // 예전에는 이 오류를 그냥 삼켰다. 그래서 리더기 서버가 꺼져 있거나
            // 브라우저가 요청을 막아도 화면에는 "키링을 대주세요"만 계속 떠 있어
            // 태그해도 아무 반응이 없는 것처럼 보였다. 이제는 화면에 이유를 띄운다.
            console.error('NFC 리더기 통신 실패:', err);
            setNfcError(describeNfcError(err));
          });
      };
      poll();                              // 화면에 들어오자마자 한 번 확인
      checkNfc = setInterval(poll, 1000);
    }
    return () => { if (checkNfc) clearInterval(checkNfc); };
  }, [screen]);

  // [기능 6] 시설 마커 업데이트 - 버튼 클릭 시에만 호출
  const updateFacilities = useCallback((map, lat, lng) => {
    if (!lat || !lng || isNaN(lat) || isNaN(lng)) return;
    fetch(`${BASE_URL}/dasibom/facilities/?lat=${lat}&lng=${lng}`)
      .then(res => res.json())
      .then(response => {
        if (response.code === 200 || response.status === 'success') {
          const facilities = response.data || [];
          const { kakao } = window;
          markersRef.current.forEach(m => m.setMap(null));
          markersRef.current = [];
          facilities.forEach(f => {
            const position = new kakao.maps.LatLng(f.lat, f.lng);
            // 위험시설: 빨간색, 안전시설: 파란색 (카카오 기본 아이콘)
            const imageSrc = f.category === '위험'
              ? "https://t1.daumcdn.net/localimg/localimages/07/mapapidoc/marker_red.png"
              : "https://t1.daumcdn.net/localimg/localimages/07/2018/pc/img/marker_spot.png";
            const marker = new kakao.maps.Marker({
              map, position, title: f.name,
              image: new kakao.maps.MarkerImage(imageSrc, new kakao.maps.Size(28, 40))
            });
            // 마커 클릭 시 해당 시설 정보 표시
            kakao.maps.event.addListener(marker, 'click', () => {
              setSelectedFacility({
                name: f.name,
                address: f.address || f.road_address || '',
                phone: f.phone || f.tel || ''
              });
            });
            markersRef.current.push(marker);
          });
        }
      }).catch(err => console.error(err));
  }, []);

  // 지도 아래쪽은 주소/전화번호 칸이 덮고 있어서, 지도 요소의 한가운데는 그 칸 바로 위
  // 가장자리다. 예전에는 거기를 기준으로 삼아 시작 위치가 반쯤 가려져 보였고, 재검색도
  // 가려진 곳을 기준으로 했다. 가운데는 "실제로 보이는 부분" 의 가운데로 친다.
  // 두 점 모두 지도 요소 왼쪽 위 기준 픽셀이다.
  const mapCenterPoints = useCallback(() => {
    const { kakao } = window;
    const { clientWidth: w, clientHeight: h } = mapContainerRef.current;
    const covered = mapInfoRef.current ? mapInfoRef.current.offsetHeight : 0;
    return {
      element: new kakao.maps.Point(w / 2, h / 2),
      visible: new kakao.maps.Point(w / 2, (h - covered) / 2),
    };
  }, []);

  // [기능 7] "현재위치 재검색" 버튼 클릭 → 보이는 지도 가운데로 시설 API + 주소 업데이트
  const handleRedoSearch = useCallback(() => {
    if (!mapInstance) return;
    const { kakao } = window;
    const center = mapInstance.getProjection().coordsFromContainerPoint(mapCenterPoints().visible);
    const lat = center.getLat();
    const lng = center.getLng();
    if (isNaN(lat) || isNaN(lng)) return;

    // 시설 마커 업데이트
    updateFacilities(mapInstance, lat, lng);

    // 주소 업데이트
    new kakao.maps.services.Geocoder().coord2Address(lng, lat, (res, stat) => {
      if (stat === kakao.maps.services.Status.OK && res) {
        setCurrentAddress(res[0]?.road_address?.address_name || res[0]?.address?.address_name || "");
      }
    });
  }, [mapInstance, updateFacilities, mapCenterPoints]);

  // [기능 8] +/- 줌 버튼
  const handleZoomIn = useCallback(() => {
    if (!mapInstance) return;
    mapInstance.setLevel(mapInstance.getLevel() - 1); // 레벨 낮을수록 확대
  }, [mapInstance]);

  const handleZoomOut = useCallback(() => {
    if (!mapInstance) return;
    mapInstance.setLevel(mapInstance.getLevel() + 1); // 레벨 높을수록 축소
  }, [mapInstance]);

  // [기능 9] 세션 초기화 - 태깅 흔적을 모두 지우고 처음 화면으로
  const resetSession = useCallback(() => {
    // 진행 중인 GPS 조회가 뒤늦게 도착해도 새 세션에 얹히지 않게 번호를 올린다
    tagSessionRef.current += 1;
    setScreen('start');
    setIsTagged(false);
    setTaggedGpsData(null);
    setSelectedFacility(null);
    setSelectedCategory('전체');
    setSelectedRegion('전체');
    setListTab('finding');
    setNfcError(null);
    setBadgeError(null);
    setIdleCountdown(null);
  }, []);

  // 메뉴의 "실종자 정보" 버튼. 들어올 때는 늘 "찾는 중이에요" 탭부터 보여주고,
  // 앞사람이 골라 둔 분류와 지역도 물려받지 않게 함께 되돌린다.
  const openPersonList = useCallback(() => {
    setListTab('finding');
    setSelectedCategory('전체');
    setSelectedRegion('전체');
    setScreen('detail');
  }, []);

  // [기능 10] 무인 자동 초기화 - 조작이 없으면 경고 후 처음 화면으로
  useEffect(() => {
    // 시작 화면은 이미 초기 상태이므로 감시할 필요가 없다
    if (screen === 'start') {
      setIdleCountdown(null);
      return;
    }

    let warnTimer = null;
    let tickTimer = null;

    const clearTimers = () => {
      clearTimeout(warnTimer);
      clearInterval(tickTimer);
    };

    // 경고를 띄우고 1초씩 세다가 0이 되면 초기화
    const startWarning = () => {
      let left = Math.ceil(IDLE_RESET_MS / 1000);
      setIdleCountdown(left);
      tickTimer = setInterval(() => {
        left -= 1;
        if (left <= 0) {
          clearTimers();
          resetSession();
        } else {
          setIdleCountdown(left);
        }
      }, 1000);
    };

    const schedule = () => {
      clearTimers();
      setIdleCountdown(null);
      warnTimer = setTimeout(startWarning, IDLE_WARN_MS);
    };

    rescheduleIdleRef.current = schedule;
    schedule();

    // 화면 어디를 건드리든 타이머를 되감는다 (지도 드래그 포함)
    const events = ['pointerdown', 'keydown', 'wheel', 'touchstart'];
    events.forEach(e => window.addEventListener(e, schedule, { passive: true }));
    return () => {
      clearTimers();
      events.forEach(e => window.removeEventListener(e, schedule));
    };
  }, [screen, resetSession]);

  // [긴급신고] 키오스크 이름만 백엔드로 전송 (뱃지 태그 불필요)
  const handleEmergency = async () => {
    try {
      const res = await fetch(`${BASE_URL}/dasibom/emergency/`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          device_code: DEVICE_ID,
          timestamp: new Date().toISOString()
        })
      });
      if (res.ok) {
        alert('긴급신고가 전송되었습니다.');
      } else {
        alert('신고 전송에 실패했습니다. 다시 시도해주세요.');
      }
    } catch (err) {
      console.error('긴급신고 오류:', err);
      alert('네트워크 오류가 발생했습니다.');
    }
  };

  // [현재위치공유] 태깅 시점에 저장된 GPS를 백엔드로 전송 (뱃지 태그 필요)
  const handleShareLocation = async () => {
    if (!taggedGpsData) {
      alert('GPS 데이터가 없습니다. 뱃지를 다시 태그해주세요.');
      return;
    }
    try {
      const res = await fetch(`${BASE_URL}/dasibom/location/`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          device_code: DEVICE_ID,
          lat: taggedGpsData.lat,
          lng: taggedGpsData.lng,
          timestamp: new Date().toISOString()
        })
      });
      if (res.ok) {
        alert('현재 위치가 보호자에게 공유되었습니다.');
      } else {
        alert('위치 공유에 실패했습니다. 다시 시도해주세요.');
      }
    } catch (err) {
      console.error('위치공유 오류:', err);
      alert('네트워크 오류가 발생했습니다.');
    }
  };

  // [지도 초기화] 안전 지도에 들어올 때마다 MAP_START 에서 시작한다
  useEffect(() => {
    if (screen !== 'map') return;
    const { kakao } = window;

    if (!mapInstance) {
      if (kakao && mapContainerRef.current) {
        kakao.maps.load(() => {
          const map = new kakao.maps.Map(mapContainerRef.current, {
            center: new kakao.maps.LatLng(MAP_START.lat, MAP_START.lng),
            level: MAP_START_LEVEL,
            disableDoubleClickZoom: true, // 터치 오작동 방지
          });
          // 시설 로드는 mapInstance 가 생기면 아래 분기에서 한 번만 한다
          setMapInstance(map);
        });
      }
      return;
    }

    // 지도는 한 번 만들어 계속 재사용한다. 예전에는 만들 때만 시작 위치를 잡아서,
    // 앞사람이 지도를 끌어 두거나 재검색해 두면 다음 사람은 그 자리에서 시작했다.
    // 숨겨져 있던(display:none) 지도는 크기를 다시 재야 중심이 맞으므로 relayout 뒤에 옮긴다.
    // 시설 정보 칸도 앞사람이 누른 시설이 남지 않게 비운다.
    const timer = setTimeout(() => {
      mapInstance.relayout();
      mapInstance.setLevel(MAP_START_LEVEL);
      // 먼저 지도 요소 한가운데에 두고, 보이는 부분 가운데로 올라오도록 중심을 그 차이만큼 내린다
      mapInstance.setCenter(new kakao.maps.LatLng(MAP_START.lat, MAP_START.lng));
      const { element, visible } = mapCenterPoints();
      mapInstance.setCenter(mapInstance.getProjection().coordsFromContainerPoint(
        new kakao.maps.Point(element.x, element.y * 2 - visible.y)
      ));
      setSelectedFacility(null);
      updateFacilities(mapInstance, MAP_START.lat, MAP_START.lng);
    }, 100);
    return () => clearTimeout(timer);
  }, [screen, mapInstance, updateFacilities, mapCenterPoints]);

  return (
    <div className="main-container">
      <div className="top-cam-area">
        <video
          ref={videoRef}
          autoPlay
          playsInline
          muted
          className="cam-video"
        />
      </div>
      <div className="content-area">

        {/* 시작 화면 슬라이드 */}
        {screen === 'start' && (
          <div className="screen-center start-slide-container">
            {slides.length > 0 ? (
              <>
                <div className="slide-card">
                  <div className={`slide-tag ${slides[currentSlide].type === '장기 실종' ? 'long' : 'short'}`}>
                    {slides[currentSlide].type}
                  </div>
                  <div className="img-main-container">
                    <Photo src={slides[currentSlide].img} className="slide-img" />
                  </div>
                  <div className="slide-info-container">
                    <p className="main-text">{slides[currentSlide].name}</p>
                    <div className="sub-info-grid">
                      <p className="sub-info-item">나이: <span>{slides[currentSlide].age}세</span></p>
                      <p className="sub-info-item">성별: <span>{slides[currentSlide].gender}</span></p>
                      <p className="sub-info-item">정보: <span>{slides[currentSlide].category}</span></p>
                    </div>
                  </div>
                </div>
                <div className="slide-dots">
                  {slides.map((_, i) => (
                    <div key={i} className={`dot ${currentSlide === i ? 'active' : ''}`} onClick={() => setCurrentSlide(i)}></div>
                  ))}
                </div>
              </>
            ) : (
              <div className="loading-box">
                {slidesError ? <span className="load-error">⚠ {slidesError}</span> : '데이터 로딩 중...'}
              </div>
            )}
            <button className="btn-start" onClick={() => setScreen('main')}>시작하기</button>
          </div>
        )}

        {/* 메인 메뉴 */}
        {screen === 'main' && (
          <div className="menu-grid">
            <div className="menu-item" onClick={handleEmergency}><img src="/siren.png" alt="" className="menu-icon" />긴급 신고</div>
            <div className="menu-item" onClick={openPersonList}><img src="/find.png" alt="" className="menu-icon" />실종자 정보</div>
            {/* isTagged 여부와 무관하게 항상 다시 태그를 받는다.
                tagWait 에서 "돌아가기"를 누르면 isTagged=true 인 채로 메인에 남는데,
                예전처럼 곧장 tagDone 으로 보내면 다음 사람이 태그 없이 통과한다. */}
            <div className="menu-item highlight" onClick={() => setScreen('tagWait')}><img src="/admin.png" alt="" className="menu-icon" />키링 태그</div>
            <div className="menu-item" onClick={() => setScreen('map')}><img src="/map.png" alt="" className="menu-icon" />안전 지도</div>
          </div>
        )}

        {/* 태그 대기 화면 */}
        {screen === 'tagWait' && (
          <div className="screen-center">
            <div className="tag-box">
              <h2 className="tag-title">키링을 대주세요</h2>
              <p className="tag-desc">NFC 리더기에 접촉하세요.</p>
            </div>
            {/* 리더기와 통신이 안 되면 그대로 두지 않고 이유를 보여준다 */}
            {nfcError && <p className="tag-error">⚠ {nfcError}</p>}
            {/* 등록 안 된 카드를 댔을 때. 리더기 오류와 문구를 구분해 준다 */}
            {badgeError && <p className="tag-error">⚠ {badgeError}</p>}
            <button
              className="btn-back"
              onClick={() => { setBadgeError(null); setScreen('main'); }}
            >◀ 돌아가기</button>
          </div>
        )}

        {/* 태그 완료 화면 - 버튼 5개 (보호자연락+위치공유 합침) */}
        {screen === 'tagDone' && (
          <div className="menu-grid five-buttons">
            <div className="menu-item" onClick={handleEmergency}><img src="/siren.png" alt="" className="menu-icon" />긴급 신고</div>
            <div className="menu-item" onClick={openPersonList}><img src="/find.png" alt="" className="menu-icon" />실종자 정보</div>
            <div className="menu-item" onClick={() => setScreen('tagWait')}><img src="/admin.png" alt="" className="menu-icon" />키링 태그</div>
            <div className="menu-item" onClick={() => setScreen('map')}><img src="/map.png" alt="" className="menu-icon" />안전 지도</div>
            <div className={`menu-item wide-btn ${taggedGpsData ? "highlight" : "disabled-btn"}`} onClick={taggedGpsData ? handleShareLocation : null}>
              <img src="/Group.png" alt="" className="menu-icon" />
              보호자에게 현재위치공유
              {/* 회색으로 잠겼을 때 고장으로 오해하지 않도록 이유를 적어둔다 */}
              {!taggedGpsData && (
                <span className="btn-note">현재 위치를 확인할 수 없어 사용할 수 없습니다</span>
              )}
            </div>
          </div>
        )}

        {/* 실종자 상세 정보 */}
        {screen === 'detail' && (
          <div className="detail-page">
            <div className="nav-bar">
              <span className="nav-btn" onClick={() => setScreen(isTagged ? 'tagDone' : 'main')}>◀</span>
              <span className="nav-title">실종자 상세 정보</span>
              <span className="nav-btn" onClick={resetSession}>
                <img src="/home.png" alt="홈" className="nav-icon" />
              </span>
            </div>
            {/* 찾는 중이에요 / 보호 중이에요 탭 */}
            <div className="list-tabs">
              {LIST_TABS.map(tab => (
                <div
                  key={tab.key}
                  className={`list-tab ${listTab === tab.key ? 'active' : ''}`}
                  onClick={() => setListTab(tab.key)}
                >{tab.label}</div>
              ))}
            </div>
            <div className="category-tabs">
              {categories.map(cat => (
                <div key={cat} className={`tab ${selectedCategory === cat ? 'active' : ''}`} onClick={() => setSelectedCategory(cat)}>{cat}</div>
              ))}
            </div>
            {/* 지역은 17개라 한 줄에 다 안 들어가서 옆으로 밀어 본다 */}
            <div className="region-chips">
              {regions.map(region => (
                <div key={region} className={`region-chip ${selectedRegion === region ? 'active' : ''}`} onClick={() => setSelectedRegion(region)}>{region}</div>
              ))}
            </div>
            <div className="info-grid" ref={listScrollRef}>
              {isLoading && <div className="loading-box">로딩 중...</div>}
              {!isLoading && listError && (
                <div className="loading-box"><span className="load-error">⚠ {listError}</span></div>
              )}
              {!isLoading && !listError && visiblePersons.length === 0 && (
                <div className="loading-box">해당 조건의 정보가 없습니다.</div>
              )}
              {!isLoading && visiblePersons.map(person => (
                <div className="info-card" key={person.id}>
                  <div className="card-tag">{person.type}</div>
                  <div className="card-img-container">
                    <Photo src={person.img} className="card-img" />
                  </div>
                  <div className="card-info">
                    <p>이름 : {person.name}</p>
                    <p>성별 : {person.gender}</p>
                    <p>나이 : {person.age != null ? `${person.age}세` : '-'}</p>
                    <p>등록 : {person.registeredDate || '-'}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* 안전 지도 */}
        <div className="map-page" style={{ display: screen === 'map' ? 'flex' : 'none', height: '100%', flexDirection: 'column' }}>

          {/* 카카오맵 본체 */}
          <div id="map-container" ref={mapContainerRef} style={{ width: '100%', flex: 1 }}></div>

          {/* 현재위치 재검색 버튼 (지도 위 중앙) */}
          <div className="redo-search-container">
            <button className="btn-redo-search" onClick={handleRedoSearch}>
              현재위치 재검색
            </button>
          </div>

          {/* 범례 (지도 위 왼쪽) */}
          <div className="map-legend">
            <div className="legend-item">
              <img src="/red.png" alt="위험" className="legend-icon" />
              <span>위험시설 위치</span>
            </div>
            <div className="legend-item">
              <img src="/blue.png" alt="안전" className="legend-icon" />
              <span>안전시설 위치</span>
            </div>
          </div>

          {/* 줌 인/아웃 버튼 (지도 우측) */}
          <div className="map-zoom-control">
            <button className="zoom-btn" onClick={handleZoomIn}>＋</button>
            <button className="zoom-btn" onClick={handleZoomOut}>－</button>
          </div>

          {/* 하단 정보 영역 */}
          <div className="map-info-area" ref={mapInfoRef}>
            {/* 뒤로가기 / 홈 버튼 */}
            <div className="map-nav">
              <span className="nav-btn-map" onClick={() => setScreen(isTagged ? 'tagDone' : 'main')}>◀</span>
              <span className="home-btn-map" onClick={resetSession}>
                <img src="/home.png" alt="홈" className="map-nav-icon" />
              </span>
            </div>
            {/* 시설 클릭 시 정보 표시 */}
            <div className="facility-info-box">
              <div className="info-row">
                <label>주소</label>
                <input type="text" className="map-info-input" value={selectedFacility?.address || ''} readOnly placeholder="시설을 선택하세요" />
              </div>
              <div className="info-row">
                <label>전화번호</label>
                <input type="text" className="map-info-input" value={selectedFacility?.phone || ''} readOnly placeholder="" />
              </div>
            </div>
          </div>
        </div>

      </div>
      <div className="footer">
        <div className="call-box">📞 112</div>
        <div className="call-box">📞 182</div>
      </div>

      {/* 자동 초기화 직전 경고. 화면 아무 곳이나 눌러도 타이머가 되감긴다 */}
      {idleCountdown !== null && (
        <div className="idle-overlay">
          <div className="idle-box">
            <p className="idle-title">계속 사용하시겠어요?</p>
            <p className="idle-desc">
              <strong>{idleCountdown}초</strong> 후 처음 화면으로 돌아갑니다.
            </p>
            <button
              className="btn-idle-continue"
              onClick={() => rescheduleIdleRef.current()}
            >
              계속하기
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;