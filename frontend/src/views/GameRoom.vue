<script setup>
import { onMounted } from 'vue';
import { useStarknetStore } from '../stores/starknet';
import { useGameRoomStore } from '../stores/game_room';
import { useGameRoomFactoryStore } from '../stores/game_room_factory';

const starknetStore = useStarknetStore();
const gameRoomStore = useGameRoomStore();
const gameRoomFactoryStore = useGameRoomFactoryStore();

function inviteLink() {
    const splitUrl = window.location.href.split("/");
    const text = `${splitUrl[0]}//${splitUrl[2]}/join?room=${gameRoomStore.currentGameRoom}`;
    navigator.clipboard.writeText(text).then(function () {
        document.getElementById('copied').className = 'copiedNotificationText';
        setTimeout(() => { document.getElementById('copied').className = 'hide'; }, 2000);
    }, function (err) {
        console.error('Async: Could not copy text: ', err);
    });
}

onMounted(() => {
    gameRoomFactoryStore.updateGameRoom();
    starknetStore.resetTransaction();
});
</script>

<template>
    <div class="flex column flex-center max-height-without-navbar">
        <div class="flex column flex-center">
            <div class="logo">Game Room</div>
            <div class="room_address">{{ gameRoomStore.currentGameRoom }}</div>
            
            <div class="flex column flex-center" v-if="starknetStore.transaction.status == null">
                <div v-if="true" class="flex column flex-center">
                    <div class="inline-spinner"></div>
                    <div class="info">Waiting for opponent to join...</div>

                    <div class="button big-button" @click="inviteLink()">COPY INVITE LINK</div>
                    <div class="button big-button" @click="gameRoomStore.closeRoom()">CLOSE ROOM</div>
                </div>
                <div v-else class="flex column flex-center">
                    <div class="button big-button">CLOSE ROOM</div>
                </div>
            </div>
            <TransactionStatus v-else />
        </div>
    </div>

    <div class='copiedNotification'>
        <div id="copied" class="hide">Copied</div>
    </div>
</template>

<style scoped>
.logo {
    font-size: 65px;
    line-height: 65px;
}

.room_address {
    font-size: 12px;
    letter-spacing: 1.15px;
}

.info {
    margin-top: 15px;
    text-align: center;
}

.inline-spinner {
    margin-top: 25px;
}

.copiedNotification {
    position: fixed;
    bottom: 0px;
    height: 4rem;
    overflow: hidden;
    padding: 0;
    margin-bottom: 16px;
    color: var(--white);
}

.copiedNotificationText {
    animation: 2s anim-lineUp ease-out infinite;
}

.hide {
    opacity: 0;
}

@keyframes anim-lineUp {
    0% {
        opacity: 0;
        transform: translateY(80%);
    }

    30% {
        opacity: 1;
        transform: translateY(0%);
    }

    80% {
        opacity: 1;
        transform: translateY(0%);
    }

    100% {
        opacity: 0;
        transform: translateY(0%);
    }
}
</style>