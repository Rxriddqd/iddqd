/**
 * Components V2 builder utilities
 * 
 * Provides helper functions for constructing Components V2 payloads
 * with consistent formatting and minimal boilerplate.
 */

import {
  V2Type,
  ButtonStyle,
  MessageFlags,
  type V2Button,
  type V2TextDisplay,
  type V2Separator,
  type V2Container,
  type V2Section,
  type V2ActionRow,
  type V2MessagePayload,
  type V2TopLevel,
  type V2ActionRowChild,
} from '../../types/Componentsv2.js';

/**
 * Create a base V2 message payload with the IS_COMPONENTS_V2 flag
 */
export function baseV2(): V2MessagePayload {
  return {
    flags: MessageFlags.IS_COMPONENTS_V2,
    components: [],
    allowed_mentions: { parse: [] },
  };
}

/**
 * Create a text display component
 */
export function text(content: string): V2TextDisplay {
  return {
    type: V2Type.TEXT_DISPLAY,
    content,
  };
}

/**
 * Create a button component
 */
export function button(
  label: string,
  customId: string,
  style: ButtonStyle = ButtonStyle.PRIMARY,
  disabled = false
): V2Button {
  return {
    type: V2Type.BUTTON,
    style,
    label,
    custom_id: customId,
    disabled,
  };
}

/**
 * Create a link button component
 */
export function linkButton(label: string, url: string, disabled = false): V2Button {
  return {
    type: V2Type.BUTTON,
    style: ButtonStyle.LINK,
    label,
    url,
    disabled,
  };
}

/**
 * Create an action row with buttons
 */
export function actionRow(components: V2ActionRowChild[]): V2ActionRow {
  return {
    type: V2Type.ACTION_ROW,
    components,
  };
}

/**
 * Create a separator component
 */
export function separator(divider = true, spacing: 1 | 2 = 1): V2Separator {
  return {
    type: V2Type.SEPARATOR,
    divider,
    spacing,
  };
}

/**
 * Create a section component with text and accessory
 */
export function section(
  texts: V2TextDisplay[],
  accessory: V2Button
): V2Section {
  return {
    type: V2Type.SECTION,
    components: texts,
    accessory,
  };
}

/**
 * Create a container component
 */
export function container(
  components: V2TopLevel[],
  accentColor?: number,
  spoiler = false
): V2Container {
  return {
    type: V2Type.CONTAINER,
    components,
    accent_color: accentColor,
    spoiler,
  };
}

/**
 * Convert hex color string to RGB integer
 */
export function hexToRgb(hex: string): number {
  const cleaned = hex.replace(/^#/, '');
  return parseInt(cleaned, 16);
}
