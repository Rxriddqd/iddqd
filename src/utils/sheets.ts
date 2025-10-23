/**
 * Google Sheets integration utilities
 * 
 * Provides helper functions for interacting with Google Sheets API
 */

import { google } from 'googleapis';
import { env } from '../config/env.js';
import { logger } from '../core/logger.js';

/**
 * Get authenticated Google Sheets client
 */
export function getSheets() {
  if (!env.GOOGLE_SERVICE_ACCOUNT_EMAIL || !env.GOOGLE_PRIVATE_KEY) {
    throw new Error('Google Sheets credentials not configured');
  }

  const auth = new google.auth.GoogleAuth({
    credentials: {
      client_email: env.GOOGLE_SERVICE_ACCOUNT_EMAIL,
      private_key: env.GOOGLE_PRIVATE_KEY.replace(/\\n/g, '\n'),
    },
    scopes: ['https://www.googleapis.com/auth/spreadsheets'],
  });

  return google.sheets({ version: 'v4', auth });
}

/**
 * Read values from a sheet range
 */
export async function readSheetRange(
  spreadsheetId: string,
  range: string
): Promise<any[][]> {
  try {
    const sheets = getSheets();
    const response = await sheets.spreadsheets.values.get({
      spreadsheetId,
      range,
    });

    return response.data.values || [];
  } catch (error) {
    logger.error({ error, spreadsheetId, range }, 'Failed to read sheet range');
    throw error;
  }
}

/**
 * Write values to a sheet range
 */
export async function writeSheetRange(
  spreadsheetId: string,
  range: string,
  values: any[][]
): Promise<void> {
  try {
    const sheets = getSheets();
    await sheets.spreadsheets.values.update({
      spreadsheetId,
      range,
      valueInputOption: 'RAW',
      requestBody: {
        values,
      },
    });
  } catch (error) {
    logger.error({ error, spreadsheetId, range }, 'Failed to write sheet range');
    throw error;
  }
}

/**
 * Append values to a sheet
 */
export async function appendSheetRange(
  spreadsheetId: string,
  range: string,
  values: any[][]
): Promise<void> {
  try {
    const sheets = getSheets();
    await sheets.spreadsheets.values.append({
      spreadsheetId,
      range,
      valueInputOption: 'RAW',
      requestBody: {
        values,
      },
    });
  } catch (error) {
    logger.error({ error, spreadsheetId, range }, 'Failed to append to sheet');
    throw error;
  }
}
