/* docs/prototype/scripts/fixtures.js */
const POSES_FIXTURES = [
  {
    id: "standing",
    title: "Standing",
    tag: "Mine",
    tagColor: "green",
    hearts: null,
    category: "my-poses",
    source: "personal",
    visibility: "personal",
    metadata: {
      author: "You",
      context: "Saved locally",
      difficulty: null,
      tries: null,
      saves: null
    },
    svg: `<svg viewBox="0 0 24 24" class="nb-stick-figure">
      <circle cx="12" cy="7" r="3"/>
      <line x1="12" y1="10" x2="12" y2="17"/>
      <line x1="12" y1="12" x2="7" y2="15"/>
      <line x1="12" y1="12" x2="17" y2="15"/>
      <line x1="12" y1="17" x2="8" y2="22"/>
      <line x1="12" y1="17" x2="16" y2="22"/>
    </svg>`
  },
  {
    id: "dancing",
    title: "Dancing",
    tag: "Hot",
    tagColor: "pink",
    hearts: "2.1K",
    category: "community",
    source: "community",
    visibility: "published",
    metadata: {
      author: "@posemaster",
      context: "Published",
      difficulty: "Intermediate",
      tries: "1.2K",
      saves: "456"
    },
    svg: `<svg viewBox="0 0 24 24" class="nb-stick-figure">
      <circle cx="12" cy="6" r="3"/>
      <line x1="12" y1="9" x2="11" y2="15"/>
      <line x1="11" y1="11" x2="6" y2="8"/>
      <line x1="11" y1="11" x2="17" y2="13"/>
      <line x1="11" y1="15" x2="7" y2="21"/>
      <line x1="11" y1="15" x2="16" y2="17"/>
      <line x1="16" y1="17" x2="19" y2="21"/>
    </svg>`
  },
  {
    id: "jumping",
    title: "Jumping",
    tag: "Mine",
    tagColor: "green",
    hearts: null,
    category: "my-poses",
    source: "personal",
    visibility: "personal",
    metadata: {
      author: "You",
      context: "Saved locally",
      difficulty: "Beginner",
      tries: null,
      saves: null
    },
    svg: `<svg viewBox="0 0 24 24" class="nb-stick-figure">
      <circle cx="12" cy="5" r="3"/>
      <line x1="12" y1="8" x2="12" y2="14"/>
      <line x1="12" y1="10" x2="6" y2="7"/>
      <line x1="12" y1="10" x2="18" y2="7"/>
      <line x1="12" y1="14" x2="8" y2="19"/>
      <line x1="12" y1="14" x2="16" y2="19"/>
    </svg>`
  },
  {
    id: "walking",
    title: "Walking",
    tag: null,
    tagColor: null,
    hearts: "856",
    category: "community",
    source: "community",
    visibility: "published",
    metadata: {
      author: null,
      context: "Published",
      difficulty: null,
      tries: "856",
      saves: null
    },
    svg: `<svg viewBox="0 0 24 24" class="nb-stick-figure">
      <circle cx="12" cy="7" r="3"/>
      <line x1="12" y1="10" x2="12" y2="16"/>
      <line x1="12" y1="12" x2="8" y2="15"/>
      <line x1="12" y1="12" x2="16" y2="14"/>
      <line x1="12" y1="16" x2="9" y2="22"/>
      <line x1="12" y1="16" x2="14" y2="20"/>
      <line x1="14" y1="20" x2="17" y2="22"/>
    </svg>`
  },
  {
    id: "arms-up",
    title: "Arms Up",
    tag: "New",
    tagColor: "yellow",
    hearts: null,
    category: "my-poses",
    source: "personal",
    visibility: "personal",
    metadata: {
      author: "You",
      context: "Saved locally",
      difficulty: null,
      tries: null,
      saves: null
    },
    svg: `<svg viewBox="0 0 24 24" class="nb-stick-figure">
      <circle cx="12" cy="8" r="3"/>
      <line x1="12" y1="11" x2="12" y2="18"/>
      <line x1="12" y1="13" x2="7" y2="8"/>
      <line x1="12" y1="13" x2="17" y2="8"/>
      <line x1="12" y1="18" x2="8" y2="23"/>
      <line x1="12" y1="18" x2="16" y2="23"/>
    </svg>`
  },
  {
    id: "sitting",
    title: "Sitting",
    tag: null,
    tagColor: null,
    hearts: "423",
    category: "community",
    source: "community",
    visibility: "published",
    metadata: {
      author: "@community_core",
      context: "Published",
      difficulty: "Beginner",
      tries: null,
      saves: "423"
    },
    svg: `<svg viewBox="0 0 24 24" class="nb-stick-figure">
      <circle cx="12" cy="9" r="3"/>
      <line x1="12" y1="12" x2="12" y2="18"/>
      <line x1="12" y1="14" x2="7" y2="15"/>
      <line x1="12" y1="14" x2="17" y2="15"/>
      <line x1="12" y1="18" x2="17" y2="18"/>
      <line x1="17" y1="18" x2="17" y2="23"/>
      <line x1="12" y1="18" x2="8" y2="23"/>
    </svg>`
  }
];

const POSE_DELETED_STORAGE_KEY = "ai-pose.prototype.deleted-poses";
let inMemoryDeletedPoseIds = new Set();

function getDeletedPoseIds() {
  const ids = new Set(inMemoryDeletedPoseIds);

  try {
    const storedIds = JSON.parse(sessionStorage.getItem(POSE_DELETED_STORAGE_KEY) || "[]");
    if (Array.isArray(storedIds)) {
      storedIds.forEach(id => ids.add(String(id)));
    }
  } catch (error) {
    // The prototype still keeps the change in memory when storage is unavailable.
  }

  return ids;
}

function markPoseDeleted(poseId) {
  const id = String(poseId);
  const ids = getDeletedPoseIds();
  ids.add(id);
  inMemoryDeletedPoseIds = ids;

  try {
    sessionStorage.setItem(POSE_DELETED_STORAGE_KEY, JSON.stringify([...ids]));
  } catch (error) {
    // Memory-backed state is sufficient for the current prototype session.
  }

  return true;
}

function getVisiblePoseFixtures() {
  const deletedIds = getDeletedPoseIds();
  return POSES_FIXTURES.filter(pose => !(pose.category === "my-poses" && deletedIds.has(pose.id)));
}

function getPoseCategoryFromSource(source) {
  if (source === "community") return "community";
  if (source === "my-poses" || source === "personal") return "my-poses";
  return null;
}

function getPoseByReference(poseId, source) {
  const hasSource = source !== null && source !== undefined && source !== "";
  const category = getPoseCategoryFromSource(source);
  const candidates = getVisiblePoseFixtures();

  if (hasSource && !category) return null;

  return candidates.find(pose => {
    const categoryMatches = category ? pose.category === category : true;
    return categoryMatches && pose.id === poseId;
  }) || null;
}

function getPoseSourceLabel(pose) {
  return pose.category === "community" ? "Community" : "My Pose";
}

function getPoseRoute(pose, origin) {
  const source = encodeURIComponent(pose.category);
  const id = encodeURIComponent(pose.id);
  return pose.category === "community"
    ? `pose-detail-saved.html?state=unsaved&source=${source}&origin=${encodeURIComponent(origin || "community")}&id=${id}`
    : `pose-detail.html?source=${source}&id=${id}`;
}

function getPrototypeState() {
  const params = new URLSearchParams(window.location.search);
  return params.get("state") || "ready";
}

function escapePrototypeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

window.PosePrototype = {
  escapeHtml: escapePrototypeHtml,
  getDeletedPoseIds,
  getPoseByReference,
  getPoseRoute,
  getPoseSourceLabel,
  getPrototypeState,
  getVisiblePoseFixtures,
  markPoseDeleted
};

const GALLERY_FIXTURES = {
  today: [
    {
      id: "gal-1",
      title: "Pose Match 1",
      tag: "Dancing",
      tagColor: "pink",
      time: "2:34 PM",
      bgGradient: "linear-gradient(135deg, #FF9A9E 0%, #FECFEF 100%)",
      photoUrl: "https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&q=80&w=300"
    },
    {
      id: "gal-2",
      title: "Pose Match 2",
      tag: "Standing",
      tagColor: "yellow",
      time: "1:12 PM",
      bgGradient: "linear-gradient(135deg, #12C2E9 0%, #C471ED 50%, #F64F59 100%)",
      photoUrl: "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&q=80&w=300"
    },
    {
      id: "gal-3",
      title: "Pose Match 3",
      tag: "Arms up",
      tagColor: "blue",
      time: "11:45 AM",
      bgGradient: "linear-gradient(135deg, #8A2387 0%, #E94057 50%, #F27121 100%)",
      photoUrl: "https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?auto=format&fit=crop&q=80&w=300"
    },
    {
      id: "gal-4",
      title: "Pose Match 4",
      tag: "Jumping",
      tagColor: "green",
      time: "10:20 AM",
      bgGradient: "linear-gradient(135deg, #3A1C71 0%, #D76D77 50%, #FFAF7B 100%)",
      photoUrl: "https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&q=80&w=300"
    }
  ],
  yesterday: [
    {
      id: "gal-5",
      title: "Pose Match 5",
      tag: "Walking",
      tagColor: "yellow",
      time: "6:15 PM",
      placeholder: true
    },
    {
      id: "gal-6",
      title: "Pose Match 6",
      tag: "Sitting",
      tagColor: "pink",
      time: "4:30 PM",
      bgGradient: "linear-gradient(135deg, #FAD961 0%, #F76B1C 100%)",
      photoUrl: "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&q=80&w=300"
    }
  ]
};
