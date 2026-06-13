import Foundation
import GRDB

public struct DatabaseMigrator {
    public init() {}

    public func migrate(databaseQueue: DatabaseQueue) throws {
        try databaseQueue.write { database in
            try database.execute(sql: Self.bootstrapSQL)

            for migration in Self.migrations {
                let existing = try Int.fetchOne(
                    database,
                    sql: "select count(*) from schema_migrations where version = ?;",
                    arguments: [migration.version]
                ) ?? 0
                guard existing == 0 else { continue }

                try database.execute(sql: migration.sql)
                try database.execute(
                    sql:
                        """
                        insert into schema_migrations(version, name, applied_at)
                        values (?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
                        """,
                    arguments: [migration.version, migration.name]
                )
            }
        }
    }

    private struct Migration {
        var version: Int
        var name: String
        var sql: String
    }

    private static let bootstrapSQL =
        """
        create table if not exists schema_migrations (
          version integer primary key,
          name text not null,
          applied_at text not null
        );
        """

    private static let migrations: [Migration] = [
        Migration(version: 1, name: "p0_core", sql: p0CoreSQL),
        Migration(version: 2, name: "p1_search_and_analysis", sql: p1SearchAndAnalysisSQL),
        Migration(version: 3, name: "p0_p1_schema_expansion", sql: p0P1SchemaExpansionSQL),
        Migration(version: 4, name: "drop_thumbnail_cache_index", sql: dropThumbnailCacheIndexSQL),
        Migration(version: 5, name: "multi_photo_source", sql: multiPhotoSourceSQL),
        Migration(version: 6, name: "p2_embeddings_and_type", sql: p2EmbeddingsAndTypeSQL),
        Migration(version: 7, name: "geo_coord_clusters", sql: geoCoordClustersSQL)
    ]

    // M2 逆地理聚类重构：坐标网格聚类去重 + photo_locations 增列（聚类引用 / geohash / 海拔）。
    // 设计要点见 doc/三大功能重构设计.md §3.2 / §5。
    // - coord_clusters 是实际发起 MKReverseGeocodingRequest 的对象（同一 ~100m 网格只反查一次）；
    // - 海拔为每张照片属性（同网格不同照片海拔不同），故存 photo_locations 而非聚类。
    private static let geoCoordClustersSQL =
        """
        create table if not exists coord_clusters (
          id integer primary key,
          grid_lat real not null,
          grid_lon real not null,
          country text,
          country_code text,
          admin1 text,
          city text,
          place_name text,
          status text not null default 'pending',
          retry_count integer not null default 0,
          last_attempt text,
          updated_at text not null,
          unique(grid_lat, grid_lon)
        );
        create index if not exists idx_coord_clusters_status on coord_clusters(status);

        alter table photo_locations add column cluster_id integer references coord_clusters(id);
        alter table photo_locations add column geohash text;
        alter table photo_locations add column altitude real;

        create index if not exists idx_photo_locations_cluster on photo_locations(cluster_id);
        create index if not exists idx_photo_locations_geohash on photo_locations(geohash);
        """

    // P2：向量空间 + 嵌入存储 + 类型(RAW)。
    // 设计要点：不同模型向量长度不同 → 用单表 photo_embeddings + space_id 区分，
    // 向量以变长 blob 保存、维度随空间记录；KNN 查询始终按 space_id 限定，确保只用指定模型的向量。
    private static let p2EmbeddingsAndTypeSQL =
        """
        create table if not exists embedding_spaces (
          id text primary key,
          model_key text not null unique,
          display_name text not null,
          dimension integer not null,
          modality text not null,
          last_used_at text,
          created_at text not null,
          updated_at text not null
        );

        create table if not exists photo_embeddings (
          photo_id text not null references photo_assets(id) on delete cascade,
          space_id text not null references embedding_spaces(id) on delete cascade,
          dimension integer not null,
          vector blob not null,
          updated_at text not null,
          primary key (photo_id, space_id)
        );

        create index if not exists idx_photo_embeddings_space on photo_embeddings(space_id);

        -- 各分析任务的「已处理」标记（标签/类型/地理位置等的幂等去重；向量用 photo_embeddings 自身判断）。
        create table if not exists photo_analysis_state (
          photo_id text not null references photo_assets(id) on delete cascade,
          kind text not null,
          analyzed_at text not null,
          primary key (photo_id, kind)
        );
        create index if not exists idx_photo_analysis_state_kind on photo_analysis_state(kind);

        alter table photo_assets add column is_raw integer not null default 0;

        insert or ignore into app_settings(key, value, updated_at)
        values ('analysis.vectorModel', 'apple.featureprint', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
        """

    // 多照片源：新增 photo_sources 表，photo_assets 增补 source 定位字段，并把存量行回填到系统源。
    // 注意：不重写 photo_assets.id（保留与 photo_scores / analysis_tasks 等外键关系），
    // 系统源 id 仍 = localIdentifier；本地源 id 由导入器生成（local_identifier 同步存同值以满足 not null unique）。
    private static let multiPhotoSourceSQL =
        """
        create table if not exists photo_sources (
          id text primary key,
          kind text not null,
          display_name text not null,
          root_bookmark blob,
          root_path text,
          is_enabled integer not null default 1,
          last_synced_at text,
          created_at text not null,
          updated_at text not null
        );

        insert or ignore into photo_sources(id, kind, display_name, is_enabled, created_at, updated_at)
        values (
          'system_photos', 'system_photos', '系统图库', 1,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        );

        alter table photo_assets add column source_id text;
        alter table photo_assets add column source_asset_key text;
        alter table photo_assets add column file_bookmark blob;
        alter table photo_assets add column relative_path text;
        alter table photo_assets add column content_hash text;
        alter table photo_assets add column file_size integer;

        update photo_assets
        set source_id = 'system_photos',
            source_asset_key = local_identifier
        where source_id is null;

        create index if not exists idx_photo_assets_source on photo_assets(source_id);
        create unique index if not exists idx_photo_assets_source_key
          on photo_assets(source_id, source_asset_key);
        create index if not exists idx_photo_assets_content_hash on photo_assets(content_hash);
        """

    // PHCachingImageManager 已提供完整的内存/磁盘缩略图缓存与可见区预热，
    // 额外维护 thumbnail_cache_index 表只增加写库 IO 而无增量价值，故移除。
    private static let dropThumbnailCacheIndexSQL =
        """
        drop table if exists thumbnail_cache_index;
        """

    private static let p0CoreSQL =
        """
        create table if not exists app_settings (
          key text primary key,
          value text not null,
          updated_at text not null
        );

        create table if not exists photo_assets (
          id text primary key,
          local_identifier text not null unique,
          filename text,
          media_type text not null,
          media_subtypes_raw integer not null default 0,
          creation_date text,
          modification_date text,
          width integer not null default 0,
          height integer not null default 0,
          duration real,
          is_favorite integer not null default 0,
          is_hidden integer not null default 0,
          in_trash integer not null default 0,
          trashed_at text,
          icloud_state text not null default 'unknown',
          is_locally_available integer,
          resource_availability_checked_at text,
          system_deleted_at text,
          imported_at text not null,
          updated_at text not null
        );

        create index if not exists idx_photo_assets_media_type on photo_assets(media_type);
        create index if not exists idx_photo_assets_creation_date on photo_assets(creation_date);
        create index if not exists idx_photo_assets_favorite on photo_assets(is_favorite);
        create index if not exists idx_photo_assets_trash on photo_assets(in_trash, trashed_at);
        create index if not exists idx_photo_assets_icloud on photo_assets(icloud_state, is_locally_available);

        create table if not exists photo_locations (
          photo_id text primary key references photo_assets(id) on delete cascade,
          latitude real,
          longitude real,
          country text,
          administrative_area text,
          locality text,
          place_name text,
          updated_at text not null
        );

        create table if not exists tag_definitions (
          id text primary key,
          tag_key text not null unique,
          display_name text not null,
          category text not null default 'user',
          source text not null default 'user',
          created_at text not null
        );

        create table if not exists photo_tags (
          photo_id text not null references photo_assets(id) on delete cascade,
          tag_id text not null references tag_definitions(id) on delete cascade,
          tag_source text not null,
          confidence real,
          created_at text not null,
          primary key(photo_id, tag_id, tag_source)
        );

        create index if not exists idx_photo_tags_tag on photo_tags(tag_id, photo_id);

        create table if not exists person_entities (
          id text primary key,
          person_key text not null unique,
          display_name text,
          created_at text not null,
          updated_at text not null
        );

        create table if not exists photo_people (
          photo_id text not null references photo_assets(id) on delete cascade,
          person_id text not null references person_entities(id) on delete cascade,
          confidence real,
          source text not null default 'user',
          created_at text not null,
          primary key(photo_id, person_id)
        );

        create index if not exists idx_photo_people_person on photo_people(person_id, photo_id);

        create table if not exists search_filters (
          id text primary key,
          name text,
          payload_json text not null,
          is_active integer not null default 0,
          created_at text not null,
          updated_at text not null
        );

        insert or ignore into app_settings(key, value, updated_at)
        values
          ('appearance.theme', 'system', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
          ('appearance.language', 'system', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
          ('photos.gridLevel', '5', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
          ('photos.badgeMetric', 'aesthetic', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
          ('analysis.visionEnabled', 'false', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
        """

    private static let p1SearchAndAnalysisSQL =
        """
        create table if not exists photo_scores (
          photo_id text primary key references photo_assets(id) on delete cascade,
          aesthetic_score real not null,
          overall_score real,
          analysis_run_id text not null,
          analysis_output_id text not null,
          model_id text not null,
          scored_at text not null,
          updated_at text not null
        );

        create index if not exists idx_photo_scores_aesthetic on photo_scores(aesthetic_score);
        create index if not exists idx_photo_scores_run on photo_scores(analysis_run_id);

        create table if not exists ai_models (
          id text primary key,
          model_role text not null,
          provider text not null,
          model_name text not null,
          model_version text not null,
          active integer not null default 1,
          created_at text not null
        );

        create unique index if not exists idx_ai_models_active_role
        on ai_models(model_role, active)
        where active = 1;

        insert or ignore into ai_models(
          id, model_role, provider, model_name, model_version, active, created_at
        )
        values (
          'apple_vision_aesthetics_v1',
          'visionAesthetics',
          'AppleVision',
          'VNCalculateImageAestheticsScoresRequest',
          'revision1',
          1,
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        );

        create table if not exists analysis_runs (
          id text primary key,
          task_type text not null,
          model_id text not null references ai_models(id),
          status text not null default 'pending',
          requested_scope_json text,
          total_count integer not null default 0,
          completed_count integer not null default 0,
          failed_count integer not null default 0,
          created_at text not null,
          started_at text,
          completed_at text
        );

        create index if not exists idx_analysis_runs_task_status on analysis_runs(task_type, status);

        create table if not exists analysis_tasks (
          id text primary key,
          analysis_run_id text not null references analysis_runs(id) on delete cascade,
          photo_id text not null references photo_assets(id) on delete cascade,
          task_type text not null,
          status text not null default 'pending',
          priority integer not null default 100,
          attempts integer not null default 0,
          locked_until text,
          error_message text,
          created_at text not null,
          started_at text,
          completed_at text,
          unique(analysis_run_id, photo_id, task_type)
        );

        create index if not exists idx_analysis_tasks_claim
        on analysis_tasks(status, priority, created_at);
        create index if not exists idx_analysis_tasks_run_status
        on analysis_tasks(analysis_run_id, status);

        create table if not exists analysis_outputs (
          id text primary key,
          analysis_run_id text not null references analysis_runs(id) on delete cascade,
          analysis_task_id text references analysis_tasks(id) on delete set null,
          photo_id text not null references photo_assets(id) on delete cascade,
          model_id text not null references ai_models(id),
          output_type text not null,
          output_payload_json text not null,
          active integer not null default 0,
          superseded_at text,
          activated_at text,
          created_at text not null
        );

        create index if not exists idx_analysis_outputs_active
        on analysis_outputs(photo_id, output_type, active);
        create index if not exists idx_analysis_outputs_run
        on analysis_outputs(analysis_run_id, output_type);

        create table if not exists photo_search_documents (
          id integer primary key autoincrement,
          photo_id text not null unique references photo_assets(id) on delete cascade,
          filename text not null default '',
          tags text not null default '',
          people text not null default '',
          place text not null default '',
          ai_text text not null default '',
          metadata text not null default '',
          updated_at text not null
        );

        create virtual table if not exists photo_search_fts using fts5(
          filename,
          tags,
          people,
          place,
          ai_text,
          metadata,
          content='photo_search_documents',
          content_rowid='id',
          tokenize='unicode61 remove_diacritics 2'
        );

        create trigger if not exists photo_search_documents_ai
        after insert on photo_search_documents begin
          insert into photo_search_fts(rowid, filename, tags, people, place, ai_text, metadata)
          values (new.id, new.filename, new.tags, new.people, new.place, new.ai_text, new.metadata);
        end;

        create trigger if not exists photo_search_documents_ad
        after delete on photo_search_documents begin
          insert into photo_search_fts(photo_search_fts, rowid, filename, tags, people, place, ai_text, metadata)
          values ('delete', old.id, old.filename, old.tags, old.people, old.place, old.ai_text, old.metadata);
        end;

        create trigger if not exists photo_search_documents_au
        after update on photo_search_documents begin
          insert into photo_search_fts(photo_search_fts, rowid, filename, tags, people, place, ai_text, metadata)
          values ('delete', old.id, old.filename, old.tags, old.people, old.place, old.ai_text, old.metadata);
          insert into photo_search_fts(rowid, filename, tags, people, place, ai_text, metadata)
          values (new.id, new.filename, new.tags, new.people, new.place, new.ai_text, new.metadata);
        end;
        """

    private static let p0P1SchemaExpansionSQL =
        """
        alter table photo_assets add column source_type text not null default 'photos_library';
        alter table photo_assets add column device_make text;
        alter table photo_assets add column device_model text;
        alter table photo_assets add column device_category text not null default 'unknown';
        alter table photo_assets add column location_id text;

        create index if not exists idx_photo_assets_device_category on photo_assets(device_category);
        create index if not exists idx_photo_assets_source_type on photo_assets(source_type);
        create index if not exists idx_photo_assets_location_id on photo_assets(location_id);

        alter table tag_definitions add column display_name_zh text;
        alter table tag_definitions add column display_name_en text;
        alter table tag_definitions add column aliases_json text;
        alter table tag_definitions add column user_confirmed integer not null default 0;

        create table if not exists person_faces (
          id text primary key,
          photo_id text not null references photo_assets(id) on delete cascade,
          person_id text references person_entities(id) on delete set null,
          face_cluster_id text,
          bounding_box_json text not null default '{}',
          quality_score real,
          featureprint_blob blob,
          confidence real,
          source text not null default 'reserved',
          user_confirmed integer not null default 0,
          created_at text not null,
          updated_at text not null
        );

        create index if not exists idx_person_faces_photo_id on person_faces(photo_id);
        create index if not exists idx_person_faces_person_id on person_faces(person_id);
        create index if not exists idx_person_faces_cluster on person_faces(face_cluster_id);

        create table if not exists albums (
          id text primary key,
          local_identifier text,
          title text not null,
          album_type text not null,
          subtype text,
          sort_order integer not null default 0,
          created_at text not null,
          updated_at text not null
        );

        create table if not exists album_assets (
          album_id text not null references albums(id) on delete cascade,
          photo_id text not null references photo_assets(id) on delete cascade,
          position integer,
          primary key(album_id, photo_id)
        );

        create index if not exists idx_album_assets_photo_id on album_assets(photo_id);

        create table if not exists timeline_events (
          id text primary key,
          event_type text not null,
          title text not null,
          subtitle text,
          start_date text,
          end_date text,
          payload_json text not null default '{}',
          created_at text not null,
          updated_at text not null
        );

        create table if not exists reports (
          id text primary key,
          report_type text not null,
          title text not null,
          summary text,
          payload_json text not null default '{}',
          generated_at text,
          created_at text not null,
          updated_at text not null
        );
        """
}
