use serde::Serde;
use array::ArrayTrait;
use option::OptionTrait;
use result::{ResultTrait, ResultTraitImpl};
use traits::{Into, TryInto};
use starknet::{StorageAccess, StorageBaseAddress, SyscallResult};
use starknet::{storage_read_syscall, storage_write_syscall, storage_address_from_base_and_offset};

const POW_2_1: u128  = 2;
const POW_2_2: u128  = 4;
const POW_2_17: u128 = 131072;
const POW_2_18: u128 = 262144;
const POW_2_33: u128 = 8589934592;
const POW_2_34: u128 = 17179869184;
const POW_2_50: u128 = 1125899906842624;
const POW_2_66: u128 = 73786976294838206464;

//***********************************************************//
//                            BALL
//***********************************************************//

#[derive(Drop, Copy, Serde)]
struct Ball {
    x: u16,
    y: u16,
    size: u16,
    speed_x: u16,
    speed_y: u16,
    moving_up: bool,
    moving_left: bool
}

impl IntoFelt252BallImpl of Into<Ball, felt252> {
    fn into(self: Ball) -> felt252 {
        let moving_left_value: u128    = if self.moving_left { 1_u128 } else { 0_u128 };
        let moving_up_value: u128      = if self.moving_up   { POW_2_1 } else { 0_u128 };
        let speed_x_value_252: felt252 = self.speed_x.into();
        let speed_x_value: u128        = speed_x_value_252.try_into().unwrap() * POW_2_2;
        let speed_y_value_252: felt252 = self.speed_y.into();
        let speed_y_value: u128        = speed_y_value_252.try_into().unwrap() * POW_2_18;
        let size_value_252: felt252    = self.size.into();       
        let size_value: u128           = size_value_252.try_into().unwrap() * POW_2_34;
        let y_value_252: felt252       = self.y.into();
        let y_value: u128              = y_value_252.try_into().unwrap() * POW_2_50;
        let x_value_252: felt252       = self.x.into();
        let x_value: u128              = x_value_252.try_into().unwrap() * POW_2_66;

        let stored_value: u128 = moving_left_value + moving_up_value + speed_x_value + speed_y_value + size_value + y_value + x_value;
        stored_value.into()
    }
}

impl IntoBallFelt252Impl of Into<felt252, Ball> {
    fn into(self: felt252) -> Ball {
        let value: u128 = self.try_into().unwrap();

        let moving_left_value: u128 = (value & 0b1);
        let moving_up_value: u128   = (value & 0b10) / POW_2_1;
        let speed_x_value: u128     = (value & 0b111111111111111100) / POW_2_2;
        let speed_y_value: u128     = (value & 0b1111111111111111000000000000000000) / POW_2_18;
        let size_value: u128        = (value & 0b11111111111111110000000000000000000000000000000000) / POW_2_34;
        let y_value: u128           = (value & 0b111111111111111100000000000000000000000000000000000000000000000000) / POW_2_50;
        let x_value: u128           = (value & 0b1111111111111111000000000000000000000000000000000000000000000000000000000000000000)/ POW_2_66;

        let speed_x_value_252: felt252     = speed_x_value.into();
        let speed_y_value_252: felt252     = speed_y_value.into();
        let size_value_252: felt252        = size_value.into();
        let y_value_252: felt252           = y_value.into();
        let x_value_252: felt252           = x_value.into();
        
        Ball {
            x: x_value_252.try_into().expect('CANT_READ_X'),
            y: y_value_252.try_into().expect('CANT_READ_Y'),
            size: size_value_252.try_into().expect('CANT_READ_SIZE'),
            speed_x: speed_x_value_252.try_into().expect('CANT_READ_SPEED_X'),
            speed_y: speed_y_value_252.try_into().expect('CANT_READ_SPEED_Y'),
            moving_up: (moving_up_value > 0_u128),
            moving_left: (moving_left_value > 0_u128)
        }
    }
}

impl IntoFelt252ArrayBallImpl of Into<Ball, Array<felt252>> {
    fn into(self: Ball) -> Array<felt252> {
        let mut felt_array: Array<felt252> = ArrayTrait::new();
        felt_array.append(self.x.into());
        felt_array.append(self.y.into());
        felt_array.append(self.size.into());
        felt_array.append(self.speed_x.into());
        felt_array.append(self.speed_y.into());
        felt_array.append(if self.moving_up { 1 } else { 0 }.into());
        felt_array.append(if self.moving_left { 1 } else { 0 }.into());
        felt_array
    }
}

impl IntoBallFelt252ArrayImpl of Into<Array<felt252>, Ball> {
    fn into(self: Array<felt252>) -> Ball {
        let felt_0 = *self.at(0);
        let felt_1 = *self.at(1);
        let felt_2 = *self.at(2);
        let felt_3 = *self.at(3);
        let felt_4 = *self.at(4);
        let felt_5 = *self.at(5);
        let felt_6 = *self.at(6);

        let moving_up_value: u128   = felt_5.try_into().unwrap();
        let moving_left_value: u128 = felt_6.try_into().unwrap();
        
        Ball {
            x: felt_0.try_into().unwrap(),
            y: felt_1.try_into().unwrap(),
            size: felt_2.try_into().unwrap(),
            speed_x: felt_3.try_into().unwrap(),
            speed_y: felt_4.try_into().unwrap(),
            moving_up: (moving_up_value > 0_u128),
            moving_left: (moving_left_value > 0_u128)
        }
    }
}

impl StorageAccessBallImpl of StorageAccess<Ball> {
    fn write(address_domain: u32, base: StorageBaseAddress, value: Ball) -> SyscallResult<()> {
        //storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), value.into());
        
        let felt_array: Array<felt252> = value.into();
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), *felt_array.at(0));
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 1_u8), *felt_array.at(1));
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 2_u8), *felt_array.at(2));
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 3_u8), *felt_array.at(3));
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 4_u8), *felt_array.at(4));
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 5_u8), *felt_array.at(5));
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 6_u8), *felt_array.at(6));

        SyscallResult::Ok(())
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Ball> {
        //let stored_value = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8))?;
        //SyscallResult::Ok(stored_value.into())

        let mut felt_array: Array<felt252> = ArrayTrait::new();
        felt_array.append(storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8))?);
        felt_array.append(storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 1_u8))?);
        felt_array.append(storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 2_u8))?);
        felt_array.append(storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 3_u8))?);
        felt_array.append(storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 4_u8))?);
        felt_array.append(storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 5_u8))?);
        felt_array.append(storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 6_u8))?);
        SyscallResult::Ok(felt_array.into())
    }
}

//***********************************************************//
//                          PADDLE
//***********************************************************//

#[derive(Drop, Copy, Serde)]
struct Paddle {
    y: u16,
    size: u16,
    speed: u16,
    moving_up: bool
}

impl IntoFelt252PaddleImpl of Into<Paddle, felt252> {
    fn into(self: Paddle) -> felt252 {
        let moving_up_value: u128    = if self.moving_up { 1_u128 } else { 0_u128 };
        let speed_value_252: felt252 = self.speed.into();
        let speed_value: u128        = speed_value_252.try_into().unwrap() * POW_2_1;
        let size_value_252: felt252  = self.size.into();
        let size_value: u128         = size_value_252.try_into().unwrap() * POW_2_17;
        let y_value_252: felt252     = self.y.into();
        let y_value: u128            = y_value_252.try_into().unwrap() * POW_2_33;

        let stored_value: u128 =  moving_up_value + speed_value + size_value + y_value;
        stored_value.into()
    }
}

impl IntoPaddleFelt252Impl of Into<felt252, Paddle> {
    fn into(self: felt252) -> Paddle {
        let value: u128 = self.try_into().unwrap();

        let moving_up_value: u128   = (value & 0b1);
        let speed_value: u128       = (value & 0b11111111111111110) / POW_2_1;
        let size_value: u128        = (value & 0b111111111111111100000000000000000) / POW_2_17;
        let y_value: u128           = (value & 0b1111111111111111000000000000000000000000000000000) / POW_2_33;

        let speed_value_252: felt252     = speed_value.into();
        let size_value_252: felt252      = size_value.into();
        let y_value_252: felt252         = y_value.into();
        
        Paddle {
            y: y_value_252.try_into().expect('CANT_READ_Y'),
            size: size_value_252.try_into().expect('CANT_READ_SIZE'),
            speed: speed_value_252.try_into().expect('CANT_READ_SPEED'),
            moving_up: (moving_up_value > 0_u128)
        }
    }
}

impl IntoFelt252ArrayPaddleImpl of Into<Paddle, Array<felt252>> {
    fn into(self: Paddle) -> Array<felt252> {
        let mut felt_array: Array<felt252> = ArrayTrait::new();
        felt_array.append(self.y.into());
        felt_array.append(self.size.into());
        felt_array.append(self.speed.into());
        felt_array.append(if self.moving_up { 1 } else { 0 }.into());
        felt_array        
    }
}

impl IntoPaddleFelt252ArrayImpl of Into<Array<felt252>, Paddle> {
    fn into(self: Array<felt252>) -> Paddle {
        let felt_0 = *self.at(0);
        let felt_1 = *self.at(1);
        let felt_2 = *self.at(2);
        let felt_3 = *self.at(3);
        let moving_up_value: u128   = felt_3.try_into().unwrap();
        
        Paddle {
            y: felt_0.try_into().unwrap(),
            size: felt_1.try_into().unwrap(),
            speed: felt_2.try_into().unwrap(),
            moving_up: (moving_up_value > 0_u128)
        }
    }
}

impl StorageAccessPaddleImpl of StorageAccess<Paddle> {
    fn write(address_domain: u32, base: StorageBaseAddress, value: Paddle) -> SyscallResult<()> {
        //storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), value.into());
        
        let felt_array: Array<felt252> = value.into();
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), *felt_array.at(0));
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 1_u8), *felt_array.at(1));
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 2_u8), *felt_array.at(2));
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 3_u8), *felt_array.at(3));
        SyscallResult::Ok(())
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Paddle> {
        //let stored_value = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8))?;
        //SyscallResult::Ok(stored_value.into())
        let mut felt_array: Array<felt252> = ArrayTrait::new();
        felt_array.append(storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8))?);
        felt_array.append(storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 1_u8))?);
        felt_array.append(storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 2_u8))?);
        felt_array.append(storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 3_u8))?);
        SyscallResult::Ok(felt_array.into())
    }
}