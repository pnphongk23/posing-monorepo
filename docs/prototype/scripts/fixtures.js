/* docs/prototype/scripts/fixtures.js */
const POSES_FIXTURES = [
  {
    id: "standing",
    title: "Standing",
    tag: "MINE",
    tagColor: "green",
    hearts: null,
    category: "my-poses",
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
    tag: "HOT",
    tagColor: "pink",
    hearts: "2.1K",
    category: "community",
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
    tag: "MINE",
    tagColor: "green",
    hearts: null,
    category: "my-poses",
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
    tag: "NEW",
    tagColor: "yellow",
    hearts: null,
    category: "my-poses",
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

const GALLERY_FIXTURES = {
  today: [
    {
      id: "gal-1",
      title: "Pose Match 1",
      tag: "DANCING",
      tagColor: "pink",
      time: "2:34 PM",
      bgGradient: "linear-gradient(135deg, #FF9A9E 0%, #FECFEF 100%)",
      photoUrl: "https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&q=80&w=300"
    },
    {
      id: "gal-2",
      title: "Pose Match 2",
      tag: "STANDING",
      tagColor: "yellow",
      time: "1:12 PM",
      bgGradient: "linear-gradient(135deg, #12C2E9 0%, #C471ED 50%, #F64F59 100%)",
      photoUrl: "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&q=80&w=300"
    },
    {
      id: "gal-3",
      title: "Pose Match 3",
      tag: "ARMS UP",
      tagColor: "blue",
      time: "11:45 AM",
      bgGradient: "linear-gradient(135deg, #8A2387 0%, #E94057 50%, #F27121 100%)",
      photoUrl: "https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?auto=format&fit=crop&q=80&w=300"
    },
    {
      id: "gal-4",
      title: "Pose Match 4",
      tag: "JUMPING",
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
      tag: "WALKING",
      tagColor: "yellow",
      time: "6:15 PM",
      placeholder: true
    },
    {
      id: "gal-6",
      title: "Pose Match 6",
      tag: "SITTING",
      tagColor: "pink",
      time: "4:30 PM",
      bgGradient: "linear-gradient(135deg, #FAD961 0%, #F76B1C 100%)",
      photoUrl: "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&q=80&w=300"
    }
  ]
};
