import { Schema } from 'firebase/ai'
import type { FunctionDeclarationsTool } from 'firebase/ai'

/**
 * Lets the model escalate when it can SEE the person moving toward using —
 * reaching for a bottle, pouring a drink, preparing a substance.
 *
 * This is deliberately a tool call rather than something inferred from the
 * transcript: the model decides, but the app owns what actually happens, so the
 * evidence capture and the caregiver alert are real, auditable side effects
 * rather than something the model merely claims to have done.
 */
export const RELAPSE_RISK_TOOL: FunctionDeclarationsTool = {
  functionDeclarations: [
    {
      name: 'flagRelapseRisk',
      description:
        'Call this ONLY when the camera clearly shows the person moving toward using a substance — ' +
        'reaching for, holding, opening, pouring, or preparing alcohol or drugs. ' +
        'Call it with stage="intervening" the first time, which captures a still frame for their ' +
        'record and lets you talk them down. If they continue anyway after you have tried to stop ' +
        'them, call it again with stage="escalated", which alerts their linked caregiver immediately. ' +
        'Never call this on a guess, on something you merely heard, or for ordinary drinks like ' +
        'water, tea, or coffee.',
      parameters: Schema.object({
        properties: {
          stage: Schema.enumString({
            enum: ['intervening', 'escalated'],
            description:
              '"intervening" = first sighting, you are about to try to stop them. ' +
              '"escalated" = you already tried and they did not stop; notify the caregiver.',
          }),
          observation: Schema.string({
            description:
              'One plain sentence describing only what you can actually see, e.g. ' +
              '"reached for a bottle on the desk and started pouring a glass". No speculation.',
          }),
        },
      }),
    },
  ],
}

export type RelapseStage = 'intervening' | 'escalated'
