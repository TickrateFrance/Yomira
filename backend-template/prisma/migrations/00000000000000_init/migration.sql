-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "username" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "reading_progress" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "manga_id" TEXT NOT NULL,
    "chapter_id" TEXT NOT NULL,
    "last_page" INTEGER NOT NULL DEFAULT 0,
    "read" BOOLEAN NOT NULL DEFAULT false,
    "chapter_number" TEXT,
    "language" TEXT,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "reading_progress_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "library" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "manga_id" TEXT NOT NULL,
    "added_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "library_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "history" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "manga_id" TEXT NOT NULL,
    "title" TEXT NOT NULL DEFAULT '',
    "cover_url" TEXT NOT NULL DEFAULT '',
    "last_read_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "history_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "app_versions" (
    "id" UUID NOT NULL,
    "platform" TEXT NOT NULL,
    "latest_version" TEXT NOT NULL,
    "min_required_version" TEXT NOT NULL,
    "url" TEXT NOT NULL DEFAULT '',
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "app_versions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_username_key" ON "users"("username");

-- CreateIndex
CREATE INDEX "reading_progress_user_id_manga_id_idx" ON "reading_progress"("user_id", "manga_id");

-- CreateIndex
CREATE UNIQUE INDEX "reading_progress_user_id_chapter_id_key" ON "reading_progress"("user_id", "chapter_id");

-- CreateIndex
CREATE INDEX "library_user_id_idx" ON "library"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "library_user_id_manga_id_key" ON "library"("user_id", "manga_id");

-- CreateIndex
CREATE INDEX "history_user_id_last_read_at_idx" ON "history"("user_id", "last_read_at");

-- CreateIndex
CREATE UNIQUE INDEX "history_user_id_manga_id_key" ON "history"("user_id", "manga_id");

-- CreateIndex
CREATE UNIQUE INDEX "app_versions_platform_key" ON "app_versions"("platform");

-- AddForeignKey
ALTER TABLE "reading_progress" ADD CONSTRAINT "reading_progress_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "library" ADD CONSTRAINT "library_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "history" ADD CONSTRAINT "history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
