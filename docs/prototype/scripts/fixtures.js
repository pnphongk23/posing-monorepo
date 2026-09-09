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

function createMockPoseSvg(arms, legs) {
  function renderLine(coordinates) {
    return '<line x1="' + coordinates[0] + '" y1="' + coordinates[1] +
      '" x2="' + coordinates[2] + '" y2="' + coordinates[3] + '"/>';
  }

  return '<svg viewBox="0 0 24 24" class="nb-stick-figure">' +
    '<circle cx="12" cy="6" r="3"/>' +
    '<line x1="12" y1="9" x2="12" y2="16"/>' +
    arms.map(renderLine).join('') +
    legs.map(renderLine).join('') +
    '</svg>';
}

const MOCK_POSE_DEMOS = [
  { id: "stretching", title: "Stretching", arms: [[12, 11, 7, 3], [12, 11, 17, 3]], legs: [[12, 16, 7, 22], [12, 16, 17, 22]] },
  { id: "warrior", title: "Warrior", arms: [[12, 11, 4, 11], [12, 11, 20, 11]], legs: [[12, 16, 7, 22], [12, 16, 18, 22]] },
  { id: "side-bend", title: "Side Bend", arms: [[12, 11, 7, 7], [12, 11, 17, 4]], legs: [[12, 16, 7, 22], [12, 16, 17, 21]] },
  { id: "squat", title: "Squat", arms: [[12, 11, 5, 10], [12, 11, 19, 10]], legs: [[12, 16, 7, 19], [7, 19, 9, 23], [12, 16, 17, 19], [17, 19, 15, 23]] },
  { id: "tree-pose", title: "Tree Pose", arms: [[12, 11, 8, 5], [12, 11, 16, 5]], legs: [[12, 16, 8, 22], [12, 16, 16, 19], [16, 19, 18, 16]] },
  { id: "lunge", title: "Lunge", arms: [[12, 11, 5, 10], [12, 11, 19, 8]], legs: [[12, 16, 7, 21], [7, 21, 5, 23], [12, 16, 17, 18], [17, 18, 20, 22]] },
  { id: "t-pose", title: "T-Pose", arms: [[12, 11, 4, 11], [12, 11, 20, 11]], legs: [[12, 16, 8, 22], [12, 16, 16, 22]] },
  { id: "star-jump", title: "Star Jump", arms: [[12, 11, 5, 5], [12, 11, 19, 5]], legs: [[12, 16, 6, 22], [12, 16, 18, 22]] },
  { id: "sitting-twist", title: "Sitting Twist", arms: [[12, 11, 6, 12], [12, 11, 18, 9]], legs: [[12, 16, 17, 17], [17, 17, 20, 22], [12, 16, 8, 20]] },
  { id: "crouch", title: "Crouch", arms: [[12, 11, 7, 12], [12, 11, 17, 12]], legs: [[12, 16, 7, 19], [7, 19, 9, 23], [12, 16, 17, 19], [17, 19, 15, 23]] },
  { id: "kneeling", title: "Kneeling", arms: [[12, 11, 7, 9], [12, 11, 17, 9]], legs: [[12, 16, 8, 19], [8, 19, 5, 19], [12, 16, 16, 19], [16, 19, 19, 19]] },
  { id: "reach-forward", title: "Reach Forward", arms: [[12, 11, 4, 12], [12, 11, 20, 12]], legs: [[12, 16, 7, 22], [12, 16, 16, 21]] },
  { id: "balance", title: "Balance", arms: [[12, 11, 6, 8], [12, 11, 18, 8]], legs: [[12, 16, 9, 22], [12, 16, 17, 16], [17, 16, 20, 20]] },
  { id: "high-kick", title: "High Kick", arms: [[12, 11, 6, 11], [12, 11, 18, 11]], legs: [[12, 16, 9, 22], [12, 16, 16, 13], [16, 13, 20, 8]] },
  { id: "prayer", title: "Prayer", arms: [[12, 11, 10, 9], [12, 11, 14, 9]], legs: [[12, 16, 8, 22], [12, 16, 16, 22]] },
  { id: "victory", title: "Victory", arms: [[12, 11, 7, 5], [12, 11, 17, 5]], legs: [[12, 16, 7, 22], [12, 16, 17, 22]] },
  { id: "runner", title: "Runner", arms: [[12, 11, 6, 8], [12, 11, 18, 13]], legs: [[12, 16, 7, 19], [7, 19, 4, 22], [12, 16, 17, 20], [17, 20, 20, 18]] },
  { id: "crossed-arms", title: "Crossed Arms", arms: [[12, 11, 7, 14], [12, 11, 17, 14]], legs: [[12, 16, 8, 22], [12, 16, 16, 22]] },
  { id: "side-lunge", title: "Side Lunge", arms: [[12, 11, 5, 8], [12, 11, 19, 8]], legs: [[12, 16, 7, 18], [7, 18, 4, 22], [12, 16, 18, 18], [18, 18, 20, 22]] },
  { id: "toe-touch", title: "Toe Touch", arms: [[12, 11, 7, 17], [12, 11, 17, 17]], legs: [[12, 16, 8, 21], [8, 21, 5, 23], [12, 16, 16, 21], [16, 21, 19, 23]] }
];

MOCK_POSE_DEMOS.forEach(function (demo) {
  POSES_FIXTURES.push({
    id: "demo-" + demo.id,
    title: demo.title,
    tag: "Demo",
    tagColor: "blue",
    hearts: null,
    category: "my-poses",
    source: "personal",
    visibility: "personal",
    metadata: {
      author: "You",
      context: "Demo fixture",
      difficulty: "Beginner",
      tries: null,
      saves: null
    },
    svg: createMockPoseSvg(demo.arms, demo.legs)
  });
});

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
