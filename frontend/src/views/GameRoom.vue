<script setup>
import { onMounted } from 'vue';
import { useStarknetStore } from '../stores/starknet';
import { useGameRoomStore } from '../stores/game_room';
import { useGameRoomFactoryStore } from '../stores/game_room_factory';
import { useRouter } from 'vue-router';
import TransactionStatus from '../components/TransactionStatus.vue';

const starknetStore = useStarknetStore();
const gameRoomStore = useGameRoomStore();
const gameRoomFactoryStore = useGameRoomFactoryStore();
const router = useRouter();

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
    starknetStore.resetTransaction();
    gameRoomStore.redirectFromStatus();
});
</script>

<template>
    <div class="flex column flex-center max-height-without-navbar">
        <div class="flex column flex-center">
            <div class="logo">Game Room</div>
            <div class="room_address">{{ gameRoomStore.currentGameRoom }}</div>

            <div class="flex column flex-center" v-if="starknetStore.transaction.status != null">
                <TransactionStatus />
            </div>
            <div v-else-if="gameRoomStore.loadingGameRoom">
                <div class="inline-spinner"></div>
            </div>
            <div v-else-if="gameRoomStore.error == null" class="flex column flex-center">
                <div class="info ">Invite another player to start the game.</div>
                <div class="deadline small">Deadline: {{ (new Date(Number(gameRoomStore.deadline * 1000))).toLocaleString() }}</div>
                <div class="button big-button" @click="inviteLink()">COPY INVITE LINK</div>
                <div class="button big-button" @click="gameRoomStore.closeRoom()">CLOSE ROOM</div>
            </div>
            <div v-else>
                <div class="info big red bold">Error: {{ gameRoomStore.error }}</div>
                <div class="button big-button" @click="gameRoomStore.closeRoom()">CLOSE ROOM</div>
            </div>
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

.label {
    margin-right: 10px;
}


.info {
    margin-top: 15px;
    text-align: center;
}

.deadline {
    margin-top: 5px;
    text-align: center;
    margin-bottom: 15px;
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