/**
 * Components V2 Type Definitions
 * 
 * These types mirror the Discord Components V2 API structure.
 * For detailed documentation, see docs/v2components.md
 */

/** Message flags constant for suppressing notifications */
export const MessageFlags = {
  SUPPRESS_NOTIFICATIONS: 1 << 12, // 4096
  IS_COMPONENTS_V2: 1 << 15, // 32768
} as const;

/** Component type enumeration matching Discord's API */
export enum V2Type {
  ACTION_ROW = 1,
  BUTTON = 2,
  STRING_SELECT = 3,
  USER_SELECT = 5,
  ROLE_SELECT = 6,
  MENTIONABLE_SELECT = 7,
  CHANNEL_SELECT = 8,
  SECTION = 9,
  TEXT_DISPLAY = 10,
  THUMBNAIL = 11,
  MEDIA_GALLERY = 12,
  FILE = 13,
  SEPARATOR = 14,
  CONTAINER = 17,
}

/** Button style enumeration */
export enum ButtonStyle {
  PRIMARY = 1,
  SECONDARY = 2,
  SUCCESS = 3,
  DANGER = 4,
  LINK = 5,
  PREMIUM = 6,
}

/** Partial emoji structure for components */
export interface PartialEmoji {
  name?: string;
  id?: string;
  animated?: boolean;
}

/** Unfurled media item structure */
export interface UnfurledMediaItem {
  url: string;
  proxy_url?: string;
  height?: number | null;
  width?: number | null;
  content_type?: string;
  attachment_id?: string;
}

/** Button component structure */
export interface V2Button {
  type: V2Type.BUTTON;
  id?: number;
  style: ButtonStyle;
  label?: string;
  emoji?: PartialEmoji;
  custom_id?: string;
  sku_id?: string;
  url?: string;
  disabled?: boolean;
}

/** String select option structure */
export interface StringSelectOption {
  label: string;
  value: string;
  description?: string;
  emoji?: PartialEmoji;
  default?: boolean;
}

/** String select component structure */
export interface V2StringSelect {
  type: V2Type.STRING_SELECT;
  id?: number;
  custom_id: string;
  options: StringSelectOption[];
  placeholder?: string;
  min_values?: number;
  max_values?: number;
  disabled?: boolean;
}

/** Select default value structure */
export interface SelectDefaultValue {
  id: string;
  type: 'user' | 'role' | 'channel';
}

/** User select component structure */
export interface V2UserSelect {
  type: V2Type.USER_SELECT;
  id?: number;
  custom_id: string;
  placeholder?: string;
  default_values?: SelectDefaultValue[];
  min_values?: number;
  max_values?: number;
  disabled?: boolean;
}

/** Role select component structure */
export interface V2RoleSelect {
  type: V2Type.ROLE_SELECT;
  id?: number;
  custom_id: string;
  placeholder?: string;
  default_values?: SelectDefaultValue[];
  min_values?: number;
  max_values?: number;
  disabled?: boolean;
}

/** Mentionable select component structure */
export interface V2MentionableSelect {
  type: V2Type.MENTIONABLE_SELECT;
  id?: number;
  custom_id: string;
  placeholder?: string;
  default_values?: SelectDefaultValue[];
  min_values?: number;
  max_values?: number;
  disabled?: boolean;
}

/** Channel select component structure */
export interface V2ChannelSelect {
  type: V2Type.CHANNEL_SELECT;
  id?: number;
  custom_id: string;
  channel_types?: number[];
  placeholder?: string;
  default_values?: SelectDefaultValue[];
  min_values?: number;
  max_values?: number;
  disabled?: boolean;
}

/** Text display component structure */
export interface V2TextDisplay {
  type: V2Type.TEXT_DISPLAY;
  id?: number;
  content: string;
}

/** Thumbnail component structure */
export interface V2Thumbnail {
  type: V2Type.THUMBNAIL;
  id?: number;
  media: UnfurledMediaItem;
  description?: string;
  spoiler?: boolean;
}

/** Media gallery item structure */
export interface MediaGalleryItem {
  media: UnfurledMediaItem;
  description?: string;
  spoiler?: boolean;
}

/** Media gallery component structure */
export interface V2MediaGallery {
  type: V2Type.MEDIA_GALLERY;
  id?: number;
  items: MediaGalleryItem[];
}

/** File component structure */
export interface V2File {
  type: V2Type.FILE;
  id?: number;
  file: UnfurledMediaItem;
  spoiler?: boolean;
  name?: string;
  size?: number;
}

/** Separator component structure */
export interface V2Separator {
  type: V2Type.SEPARATOR;
  id?: number;
  divider?: boolean;
  spacing?: 1 | 2;
}

/** Section accessory type union */
export type V2SectionAccessory = V2Button | V2Thumbnail;

/** Section component structure */
export interface V2Section {
  type: V2Type.SECTION;
  id?: number;
  components: V2TextDisplay[];
  accessory: V2SectionAccessory;
}

/** Action row child component union */
export type V2ActionRowChild =
  | V2Button
  | V2StringSelect
  | V2UserSelect
  | V2RoleSelect
  | V2MentionableSelect
  | V2ChannelSelect;

/** Action row component structure */
export interface V2ActionRow {
  type: V2Type.ACTION_ROW;
  id?: number;
  components: V2ActionRowChild[];
}

/** Container child component union */
export type V2ContainerChild =
  | V2ActionRow
  | V2TextDisplay
  | V2Section
  | V2MediaGallery
  | V2Separator
  | V2File;

/** Container component structure */
export interface V2Container {
  type: V2Type.CONTAINER;
  id?: number;
  components: V2ContainerChild[];
  accent_color?: number | null;
  spoiler?: boolean;
}

/** Top-level component union */
export type V2TopLevel =
  | V2ActionRow
  | V2TextDisplay
  | V2Section
  | V2MediaGallery
  | V2File
  | V2Separator
  | V2Container;

/** Complete message payload structure for Components V2 */
export interface V2MessagePayload {
  flags?: number;
  components?: V2TopLevel[];
  allowed_mentions?: {
    parse?: ('roles' | 'users' | 'everyone')[];
    roles?: string[];
    users?: string[];
    replied_user?: boolean;
  };
}
