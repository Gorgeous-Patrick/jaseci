import os
import time
import json
import torch
import base64
import warnings
import configparser

import numpy as np

from fastapi import HTTPException
from scipy.io.wavfile import write
from jaseci.actions.live_actions import jaseci_action
from jaseci.actions.remote_actions import launch_server

from .waveglow.denoiser import Denoiser

from .action_utils import prepare_input_sequence, load_seq2seq_model, load_vocorder_model

from speechbrain.pretrained import Tacotron2 as SpeechBrain
from speechbrain.pretrained import HIFIGAN

warnings.filterwarnings("ignore")
warnings.warn("ignore")

config = configparser.ConfigParser()
config.read(os.path.join(os.path.dirname(__file__), "config.cfg"))

force_reload = True
rate = 22050

device = ("cuda" if torch.cuda.is_available() else "cpu",)

seq2seqmodel = load_seq2seq_model("tacotron2_v1")
vocorder = load_vocorder_model("hifigan")


def prediction(input_text):
    """
    Inferencing

    Parameters:
    -----------
    input_text: String, input text for preprocessing.
    seq2seqmodel: Model, the sequence to sequence model.
    vocorder: Model, the vocorder model.
    utils: Processing,

    Return:
    -----------
    audio_numpy: Numpy array, 1d numpy with floats contains audio data.
    """

    sequences, lengths = prepare_input_sequence([input_text], cpu_run=True)

    with torch.no_grad():
        mel, _, _ = seq2seqmodel.infer(sequences, lengths)

        if vocorder.__class__.__name__ == "WAVEGLOW":
            audio = vocorder.infer(mel)
            denoiser = Denoiser(vocorder)
            audio = denoiser(audio, strength=0.05).squeeze(1)
            audio_numpy = audio[0].data.cpu().numpy()

        elif vocorder.__class__.__name__ == "HIFIGAN":
            audio = vocorder.decode_batch(mel)
            audio_numpy = audio[0].data.cpu().numpy()[0]

        else:
            print("no valid vocorder")
    return audio_numpy


def save_file(input_numpy, path="", rate=rate):
    """
    Saving the audio file the given path

    Parameters:
    -----------
    input_numpy: Numpy array, 1d numpy with floats contains audio data.
    path: String, path to the directory to save the file.
    rate: int, The rate of the audio.

    Return:
    -----------
    success: Boolean, True if successfuly saved.
    file_path: String, path to the saved file.
    """
    success = False
    ret_dict = {
        "save_status": success,
    }

    if os.path.exists(path):
        try:
            file_name = "audio_file_" + str(time.time()) + ".wav"
            file_path = os.path.join(path, file_name)
            write(file_path, rate, input_numpy)
            success = True
            ret_dict = {
                "save_status": success,
                "file_path": file_path,
            }
        except Exception as ex:
            print(ex)
            success = False
            file_path = None
    else:
        print("Set up directory path properly to save the audio file.")

    return ret_dict


@jaseci_action(act_group=["tts"], allow_remote=True)
def synthesize(
    text: str,
    seq2seq_model: str = "tacotron2",
    vocorder: str = "waveglow",
    base64_val: bool = False,
    path: str = "",
    rate: int = rate,
):
    try:
        synthesize_audio = prediction(text)
        if base64_val:
            json_encoded_list = json.dumps(synthesize_audio.tolist())
            output_list = base64.b64encode(json_encoded_list)
        else:
            output_list = synthesize_audio.tolist()

        if path != "":
            audio_data = np.array(output_list, dtype="float32")
            status = save_file(audio_data, path, rate)
            ret = {"audio_wave": output_list, "saving_status": status}
        else:
            output_list = synthesize_audio.tolist()
            ret = {
                "audio_wave": output_list,
            }
        return ret
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@jaseci_action(act_group=["tts"], allow_remote=True)
def save_audio(audio_data: list, path: str = "", rate: int = rate):
    try:
        audio_data = np.array(audio_data, dtype="float32")
        status = save_file(audio_data, path, rate)
        return status
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    print("Text to Speech Synthesizer up and running")
    """ audio = prediction(
        input_text="Text to Speech Synthesizer up and running. Mr. Jason $123", utils="utils")
    save_file(audio, "./") """
    launch_server(port=8000)
