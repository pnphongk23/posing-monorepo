PRAGMA foreign_keys = ON;
PRAGMA user_version = 1;
CREATE TABLE Pose (
  poseId TEXT PRIMARY KEY, ownerAccountId TEXT NOT NULL, name TEXT NOT NULL,
  description TEXT, tags TEXT NOT NULL DEFAULT '[]', difficulty TEXT,
  bodyParts TEXT NOT NULL DEFAULT '[]', status TEXT NOT NULL DEFAULT 'local'
    CHECK(status IN ('local', 'published')),
  originalPath TEXT NOT NULL, skeletonPath TEXT NOT NULL, thumbnailPath TEXT NOT NULL,
  currentJobId TEXT, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL
);
CREATE INDEX idx_pose_createdAt ON Pose(createdAt);
CREATE INDEX idx_pose_ownerAccountId ON Pose(ownerAccountId);
CREATE INDEX idx_pose_status ON Pose(status);
CREATE TABLE Photo (
  id INTEGER PRIMARY KEY AUTOINCREMENT, imagePath TEXT NOT NULL, poseId TEXT,
  poseName TEXT NOT NULL DEFAULT '', createdAt TEXT NOT NULL,
  isFavorite INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (poseId) REFERENCES Pose(poseId) ON DELETE SET NULL
);
CREATE INDEX idx_photo_createdAt ON Photo(createdAt);
CREATE INDEX idx_photo_poseId ON Photo(poseId);
CREATE INDEX idx_photo_isFavorite ON Photo(isFavorite);
INSERT INTO Pose VALUES (
  'pose-legacy-01','account-legacy','Legacy pose','Unicode: tạo dáng',
  '["portrait","legacy"]','medium','["arms","torso"]','local',
  'Documents/original legacy.jpg','Documents/skeleton.json','Documents/thumb.jpg',
  'job-01','1700000000000','2024-01-01T00:00:00Z'
);
INSERT INTO Photo(id,imagePath,poseId,poseName,createdAt,isFavorite) VALUES
  (41,'Documents/capture legacy.jpg','pose-legacy-01','Legacy pose','1700000000123',1),
  (42,'Documents/unlinked.jpg',NULL,'','1700000000456',0);
